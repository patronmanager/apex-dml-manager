# Overview
The purpose of DMLManager is to act as a low-risk remediation to Apex that was not architected with CRUD/FLS enforcement in mind. There are limitations, outlined below, but in 95% of cases, the additional SOQL query and retrieved row increases are far better than the risk of extensive code refactoring.

The topic is documented here:

http://wiki.developerforce.com/index.php/Testing_CRUD_and_FLS_Enforcement

and here:

https://developer.salesforce.com/page/Enforcing_CRUD_and_FLS
 
# Usage

```
List<Contact> contactList = [SELECT Id, FirstName, LastName FROM Contact];

//Manipulate the contactList
...

//Instead of calling "update contactList", use:
DMLManager.updateAsUser(contactList);
```

(there are overloaded versions of insert/update/upsert/delete that take either a single SObject or a List<SObject>)

DMLManager.CRUDException is raised for respective CRUD permission failures

DMLManager.FLSException is raised for respective FLS permission problems

# Goals
The security review team suggests using the ESAPI [SFDCAccessController](https://code.google.com/p/force-dot-com-esapi/source/browse/trunk/src/classes/SFDCAccessController.cls) for CRUD and FLS enforcement, but this implementation has serious limitations:
 * It performs DML on clones of the passed in collections of SObjects -- This results in the calling code not having access to the same object references that were ultimately used in the DML. In practice, this causes problems with Lists and other collections that are used when building Master-Detail and Lookups to a parent record persisted earlier in the transaction.
 * The insertAsUser and updateAsUser methods require a fieldsToSet collection -- this is an unreasonable burden to compute and trying to maintain a list of affected fields is a recipe for tightly coupled and unmaintainable code
 * There’s no implementation of upsertAsUser.

# Limitations
It's not all roses and gumdrops with DMLManager. There are some things to keep in mind:
* Adds an extra SOQL query for each call to insertAsUser/updateAsUser/upsertAsUser for each distinct SObjectType in the passed in collection. Additionally, since each record in the passed in collection is retrieved, the maximum query row limit (50k) per transaction may also come into play
* The current implementation of upsertAsUser does not take an External ID column as a possible key candidate for upsert. We’ll gladly accept pull requests if you want to implement this feature.
* While the code is optimized to only query the database if the calling User’s profile has FLS restricting them from access to a nonzero number of fields, in practice, there are many fields on Standard Objects that aren’t writable, but are indiscernible from fields that are FLS-restricted. For example. Opportunity.ExpectedRevenue is not a true formula field (isCalculated() is false), but it’s not writable so it is considered a restricted field and results in us needing to requery the database for existing records each time an Opportunity is passed through updateAsUser/upsertAsUser.

# Contributors

Eric Whipple [@modernapple](https://github.com/modernapple)  
David Esposito [@daveespo](https://github.com/daveespo)  
Tom Fuda [@tfuda](https://github.com/tfuda)  
Scott Covert [@scottbcovert] (https://github.com/scottbcovert)