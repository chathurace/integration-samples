import ballerina/http;
import ballerina/io;
import ballerina/mime;
import ballerina/time;
import ballerina/url;
import ballerinax/salesforce as sf;

configurable string servicenowInstance = ?;
configurable string syncData = ?;
configurable string serviceNowUsername = ?;
configurable string serviceNowPassword = ?;
configurable sf:ConnectionConfig salesforceConfig = ?;

sf:Client salesforce = check new (salesforceConfig);

public function main() returns error? {
    DateRange fetchPeriod = check calculateFetchingPeriod();
    string query = string `sys_created_onBETWEENjavascript:gs.dateGenerate(${fetchPeriod.'start})
        @javascript:gs.dateGenerate(${fetchPeriod.end})`;
    http:Client servicenow = check new (string `https://${servicenowInstance}.service-now.com/api/sn_customerservice`);
    string serviceNowCredentials = check mime:base64Encode(serviceNowUsername + ":" + serviceNowPassword, "UTF-8").ensureType();
    record {CaseData[] result;} caseResponse = check servicenow->/case(
        headers = {"Authorization": "Basic " + serviceNowCredentials},
        sysparm_query = check url:encode(query, "UTF-8")
    );
    CaseData[] cases = caseResponse.result;
    check io:fileWriteString(syncData, check time:civilToString(fetchPeriod.now));
    foreach CaseData caseData in cases {
        stream<Id, error?> customerQuery = check salesforce->query(
            string `SELECT Id FROM Account WHERE Name = '${caseData.account.name}'`);
        record {|Id value;|}? existingCustomer = check customerQuery.next();
        check customerQuery.close();
        if existingCustomer is () {
            continue;
        }
        SalesforceCase salesforceCase = {
            Name: caseData.number,
            Created_on__c: caseData.sys_created_on,
            Priority__c: caseData.priority,
            Account__c: existingCustomer.value.Id,
            Summary__c: caseData.case
        };
        _ = check salesforce->create("Support_Case__c", salesforceCase);
    }
}

function calculateFetchingPeriod() returns DateRange|error {
    string lastFetchString = check io:fileReadString(syncData);
    time:Civil lastFetch = check time:civilFromString(lastFetchString);
    string 'start = string `'${lastFetch.year}-${lastFetch.month}-${lastFetch.day}','${lastFetch.hour}:${lastFetch.minute}:00'`;
    time:Civil now = time:utcToCivil(time:utcNow());
    string end = string `'${now.year}-${now.month}-${now.day}','${now.hour}:${now.minute}:00'`;
    return {'start, end, now};
}
