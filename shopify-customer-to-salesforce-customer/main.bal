import ballerina/http;
import ballerina/log;
import ballerina/regex;
import ballerinax/salesforce as sf;

configurable sf:ConnectionConfig salesforceConfig = ?;
sf:Client salesforce = check new (salesforceConfig);

service /salesforce_bridge on new http:Listener(9090) {
    resource function post customers(@http:Payload ShopifyCustomer shopifyCustomer) returns error? {
        SalesforceCustomer salesforceCustomer = transformCustomerData(shopifyCustomer);
        error? e = updateSalesforce(salesforceCustomer);
        if e is error {
            log:printError("Error occurred while updating Salesforce for customer: " + salesforceCustomer.toJsonString(), e);
            return e;
        }
    }
}

function transformCustomerData(ShopifyCustomer shopifyCustomer) returns SalesforceCustomer {
    string firstName = shopifyCustomer.first_name ?: regex:split(shopifyCustomer.email, "@")[0];
    string lastName = shopifyCustomer.last_name ?: "";
    string address = "";
    Address? shopifyAddress = shopifyCustomer.default_address;
    if shopifyAddress !is () {
        address = string `${shopifyAddress.address1}, ${shopifyAddress.address2}, ${shopifyAddress.city}, ${shopifyAddress.country}`;
    }
    SalesforceCustomer salesforceCustomer = {
        Name: string `${firstName} ${lastName}`,
        Email__c: shopifyCustomer.email,
        Address__c: address
    };
    return salesforceCustomer;
}

function updateSalesforce(SalesforceCustomer sfCustomer) returns error? {
    stream<Id, error?> customerStream = check salesforce->query(
            string `SELECT Id FROM HmartCustomer__c WHERE Email__c = '${sfCustomer.Email__c}'`);
    record {|Id value;|}? existingCustomer = check customerStream.next();
    check customerStream.close();
    if existingCustomer is () {
        _ = check salesforce->create("HmartCustomer__c", sfCustomer);
    } else {
        check salesforce->update("HmartCustomer__c", existingCustomer.value.Id, sfCustomer);
    }
}
