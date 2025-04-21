import ballerina/time;
import ballerinax/googleapis.sheets;
import ballerinax/twilio;
import ballerina/lang.regexp;
import ballerina/log;

configurable string clientId = ?;
configurable string clientSecret = ?;
configurable string refreshToken = ?;
configurable string spreadsheetId = ?;
configurable string twilioAuthToken = ?;
configurable string twilioAccountSid = ?;
configurable string twilioFromNumber = ?;
configurable string twilioToNumber = ?;

final sheets:Client sheetsClient = check new ({
    auth: {
        clientId: clientId,
        clientSecret: clientSecret,
        refreshToken: refreshToken,
        refreshUrl: sheets:REFRESH_URL
    }
});

twilio:ConnectionConfig twilioConfig = {
    auth: {
        accountSid: twilioAccountSid,
        authToken: twilioAuthToken
    }
};
twilio:Client twilioClient = check new (twilioConfig);

public function main() returns error? {
    string[] sheetNames = ["Cheques Received", "Cheques Issued"];

    time:Utc utcNow = time:utcNow();
    time:Utc utcTimeZoneAdjusted = time:utcAddSeconds(utcNow, 19800);
    time:Civil utcTimeZoneAdjustedToday = check time:civilFromString(time:utcToString(utcTimeZoneAdjusted));

    time:Utc threeDaysUtc = time:utcAddSeconds(utcTimeZoneAdjusted, 259200);
    time:Civil threeDaysLater = check time:civilFromString(time:utcToString(threeDaysUtc));
    boolean noCheques = true;

    foreach string sheetName in sheetNames {
        sheets:Range range = check sheetsClient->getRange(
            spreadsheetId = spreadsheetId,
            sheetName = sheetName,
            a1Notation = "B2:F"
        );

        ChequeData[] todayCheques = [];
        ChequeData[] futureCheques = [];

        foreach (int|string|decimal)[] row in range.values {
            if row.length() < 5 {
                continue;
            }

            string dateStr = row[4].toString() + "T00:00:00Z";
            time:Civil chequeDate = check time:civilFromString(dateStr);
            decimal transofrmedAmout = check transformAmount(row[2].toString());

            ChequeData cheque = {
                chequeNo: row[0].toString(),
                payeeName: row[1].toString(),
                amount: transofrmedAmout,
                bank: row[3].toString(),
                chequeDate: row[4].toString()
            };

            if datesEqual(utcTimeZoneAdjustedToday, chequeDate) {
                todayCheques.push(cheque);
            } else if datesEqual(threeDaysLater, chequeDate) {
                futureCheques.push(cheque);
            }
        }

        if futureCheques.length() > 0 {
            noCheques = false;
            string message = formatMessage(sheetName, futureCheques, "in 3 days");
            check sendWhatsAppMessage(message);
        }

        if todayCheques.length() > 0 {
            noCheques = false;
            string message = formatMessage(sheetName, todayCheques, "today");
            check sendWhatsAppMessage(message);
        }
    }

    if noCheques {
        string noChequeMsg = "✅ No incoming or issued cheques due today. You're good to go!";
        check sendWhatsAppMessage(noChequeMsg);
    }
}

function datesEqual(time:Civil date1, time:Civil date2) returns boolean {
    return date1.year == date2.year && 
           date1.month == date2.month && 
           date1.day == date2.day;
}

function transformAmount(string amount) returns decimal|error {
    string amountWithoutPrefix = amount.substring(2);
    regexp:RegExp commaPattern = re `,`;
    string cleanAmount = commaPattern.replaceAll(amountWithoutPrefix, "");
    decimal value = check decimal:fromString(cleanAmount);
    return value;
}

function formatMessage(string sheetType, ChequeData[] cheques, string dueTime) returns string {
    string prefix = dueTime == "in 3 days" ? "🔔 *Reminder*" : "🚨 *Urgent*";
    string header = "";
    string action = "";

    if (sheetType == "Cheques Received") {
        header = dueTime == "in 3 days"
            ? "Deposit Cheques Soon"
            : "Deposit Cheques Today";
        action = dueTime == "in 3 days"
            ? "The following cheques can be deposited in 3 days:"
            : "The following cheques should be deposited today:";
    } else {
        header = dueTime == "in 3 days"
            ? "Ensure Funds for Issued Cheques"
            : "Funds Required for Issued Cheques Today";
        action = dueTime == "in 3 days"
            ? "Make sure the following issued cheques have sufficient balance before they are cashed:"
            : "Ensure your bank has enough funds for these issued cheques today:";
    }

    string message = string `${prefix}: ${header}
`;
    message += "--------------------------------------------------\n";
    message += (string `${action}

`);

    foreach ChequeData cheque in cheques {
        message += (string `🧾 Cheque No : ${cheque.chequeNo}` + "\n");
        message += (string `👤 Payee     : ${cheque.payeeName}` + "\n");
        message += (string `💰 Amount    : ${cheque.amount}` + "\n");
        message += (string `🏦 Bank      : ${cheque.bank}` + "\n");
        message += (string `📅 Date      : ${cheque.chequeDate}` + "\n\n");
    }

    return message;
}


function sendWhatsAppMessage(string messageBody) returns error? {
    log:printInfo("Sending WhatsApp message: " + messageBody);
    _ = check twilioClient->createMessage({
        To: string `whatsapp:${twilioToNumber}`,
        From: string `whatsapp:${twilioFromNumber}`,
        Body: messageBody
    });
}
