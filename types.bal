type ChequeData record {
    string chequeNo;
    string payeeName;
    decimal amount;
    string bank;
    string chequeDate;
};

type SheetData record {
    string sheetName;
    ChequeData[] cheques;
};