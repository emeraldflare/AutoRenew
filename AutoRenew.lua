local settings = {};
settings.RenewEmail = GetSetting("RenewEmail");
settings.DenyEmail = GetSetting("DenyEmail");
settings.LibraryUseEmail = GetSetting("LibraryUseEmail");
settings.Exclusions = GetSetting("Exclusions");

function Init()
	RegisterSystemEventHandler("SystemTimerElapsed", "AutoRenew");
end

function AutoRenew()
	
	local query = "SELECT Transactions.TransactionNumber, Transactions.UserName, Users.UserName FROM Transactions INNER JOIN Users ON Transactions.UserName = Users.UserName WHERE (TransactionStatus = 'Awaiting Renewal OK Processing' OR TransactionStatus = 'Awaiting Denied Renewal Processing')"; -- Grabs requests in renewal queues.
	
	if settings.Exclusions:match("%w") then
		 query = query .. " AND NVTGC NOT IN (" .. settings.Exclusions .. ")";
	end

	local results = PullData(query);
	if not results then
		return;
	end

	for ct = 0, results.Rows.Count - 1 do
		local tn = results.Rows:get_Item(ct):get_Item("TransactionNumber");
		ProcessDataContexts("TransactionNumber", tn, "SetDate");
	end
end

function SetDate()
	local tn = GetFieldValue("Transaction", "TransactionNumber");
	local libraryUse = GetFieldValue("Transaction", "LibraryUseOnly");
	
	local query = "SELECT TOP 1 TransactionNumber, NoteDate, Note FROM Notes WHERE TransactionNumber = '" .. tn .. "' AND (Note LIKE '% Due Date: %') ORDER BY NoteDate DESC"; -- Grabs note with renew date.
	
	local results = PullData(query);
	if not results then
		return;
	end
	
	for ct = 0, results.Rows.Count - 1 do
		local rDate = results.Rows:get_Item(ct):get_Item("Note");
			
		if rDate:match("Renewal Due Date: %d+") then
			rDate = rDate:match("Renewal Due Date: %d+"):gsub("Renewal Due Date: ", ""); 
			local year = rDate:sub(1, 4);
			local month = rDate:sub(5,6);
			local day = rDate:sub(7,8);
			
			SetFieldValue("Transaction", "DueDate", month .. "/" .. day .. "/" .. year);
			SaveDataSource("Transaction");	
			ExecuteCommand("AddNote", {tn, "[AUTO - AutoRenew - Renewal Granted]"});
			
			if libraryUse then
				ExecuteCommand("SendTransactionNotification", {tn, settings.LibraryUseEmail});
				ExecuteCommand("Route", {tn, "Customer Notified via E-Mail"});
			else
				ExecuteCommand("SendTransactionNotification", {tn, settings.RenewEmail});
				ExecuteCommand("Route", {tn, "Checked Out to Customer"});
			end

		elseif rDate:match("Renewal Denied %- Due Date: %d+") then
			rDate = rDate:match("Renewal Denied %- Due Date: %d+"):gsub("Renewal Denied %- Due Date: ", ""); 
			local year = rDate:sub(1, 4);
			local month = rDate:sub(5,6);
			local day = rDate:sub(7,8);
			
			SetFieldValue("Transaction", "DueDate", month .. "/" .. day .. "/" .. year);
			SaveDataSource("Transaction");	
			ExecuteCommand("SendTransactionNotification", {tn, settings.DenyEmail});
			ExecuteCommand("AddNote", {tn, "[AUTO - AutoRenew - Renewal Denied]"});
			
			if libraryUse then
				ExecuteCommand("Route", {tn, "Customer Notified via E-Mail"});
			else
				ExecuteCommand("Route", {tn, "Checked Out to Customer"});
			end
		end
	end
end

function PullData(query) -- Used for SQL queries that will return more than one result.
	local connection = CreateManagedDatabaseConnection();
	function PullData2()
		connection.QueryString = query;
		connection:Connect();
		local results = connection:Execute();
		connection:Disconnect();
		connection:Dispose();
		
		return results;
	end
	
	local success, results = pcall(PullData2, query);
	if not success then
		LogDebug("Problem with SQL query: " .. query .. "\nError: " .. tostring(results));
		connection:Disconnect();
		connection:Dispose();
		return false;
	end
	
	return results;
end

function OnError(errorArgs)
	LogDebug("AutoRenew had a problem! Error: " .. tostring(errorArgs));
end

