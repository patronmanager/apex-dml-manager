public class DMLManager {
	// Items in the following set must be entered in lower case
	private static Set<String> exceptionValues = new Set<String> {'id','isdeleted','createddate','systemmodstamp','lastmodifiedbyid','createdbyid','lastmodifieddate'};

	private static Map<Operation,Map<SObjectType,List<String>>> cachedRestrictedFields = new Map<Operation,Map<SObjectType,List<String>>>();
	
	public enum Operation {OP_INSERT,OP_UPDATE,OP_DELETE,OP_UPSERT}
	
	/** Convenience methods...this is what will be called from the code **/
	public static void insertAsUser(sObject objList){performDMLOperation(new List<sObject>{objList},Operation.OP_INSERT);}
	public static void updateAsUser(sObject objList){performDMLOperation(new List<sObject>{objList},Operation.OP_UPDATE);}
	public static void upsertAsUser(sObject objList){performDMLOperation(new List<sObject>{objList},Operation.OP_UPSERT);}
	public static void deleteAsUser(sObject objList){performDMLOperation(new List<sObject>{objList},Operation.OP_DELETE);}
	public static void insertAsUser(List<SObject> objList){performDMLOperation(objList,Operation.OP_INSERT);}
	public static void updateAsUser(List<SObject> objList){performDMLOperation(objList,Operation.OP_UPDATE);}
	public static void upsertAsUser(List<SObject> objList){performDMLOperation(objList,Operation.OP_UPSERT);}
	public static void deleteAsUser(List<SObject> objList){performDMLOperation(objList,Operation.OP_DELETE);}

	/** Custom Exception Classes **/
	public virtual class DMLManagerException extends Exception{
		public SObjectType objType {get; private set;}
		public Operation op{get; private set;}
	}
	public class CRUDException extends DMLManagerException{
		public CRUDException(SObjectType objType, Operation op){
			this.objType = objType;
			this.op = op;
		}
		public virtual override String getMessage(){
			return 'Access Denied: ' + op + ' on ' + objType;
		}
	}
 
	public class FLSException extends DMLManagerException{
		public SObjectField field{get; private set;}	
		public FLSException(SObjectType objType, SObjectField field, Operation op){
			this.objType = objType;
			this.op = op;
			this.field = field;
		}
 		public override String getMessage(){
			return 'Access Denied: ' + op + ' on ' + objType + '.' + field;
		}
	}
		
	private static void performDMLOperation(List<SObject> objList, Operation dmlOperation){
		Map<SObjectType,List<Id>> objTypeMap = analyzeDMLCollection(objList, dmlOperation);

		checkCRUDPermission(objTypeMap.keySet(),dmlOperation);

		if(dmlOperation == Operation.OP_INSERT){
			for(SObject obj : objList){
				checkCreateAction(obj);
			}
		} else if (dmlOperation == Operation.OP_UPDATE || dmlOperation == Operation.OP_UPSERT){
			
			Map<Id,SObject> existingRecords = getExistingRecords(objTypeMap);

			for(SObject obj : objList){
				SObject existingRecord = existingRecords.get(obj.Id);
				if((obj.Id != null) && (existingRecord == null)){
					throw new DMLManagerException('DMLManager ERROR:  An existing record could not be found for object with Id = ' + obj.Id);
				}

				if(existingRecord != null){
					checkUpdateAction(obj,existingRecord);
				} else {
					checkCreateAction(obj);
				}
			}
		}
		// If no errors have been thrown to this point, execute the dml operation.
		if(dmlOperation == Operation.OP_INSERT){insert objList;} 
			else if (dmlOperation == Operation.OP_UPDATE){update objList;} 
				else if (dmlOperation == Operation.OP_UPSERT){upsertCollection(objList);}
					else if (dmlOperation == Operation.OP_DELETE){delete objList;}
	}
	
	private static void upsertCollection(List<SObject> objList){
		//This is to deal with the call to upsertAsUser where you pass a singular SObject
		//We wrap that SObject in a List<SObject> which can't be passed into upsert 
		//This unpacks that sin and just inserts the solitary record
		if(objList.size() == 1){
			upsert objList.get(0);						
		}
		else{
			upsert objList;
		}
	} 
	
	private static Map<String,Object> getFieldMapFromExistingSObject(SObject obj){
		// Get actual fields present in object.  This serialization technique removes implicit nulls.
		String s = JSON.serialize(obj);
		Map<String,Object> fieldsMap = (Map<String,Object>) JSON.deserializeUntyped(s);
		fieldsMap.remove('attributes');
		return fieldsMap;		
	}
	
	private static void checkCreateAction(SObject obj){
		List<String> restrictedFields = cachedRestrictedFields.get(Operation.OP_INSERT).get(obj.getSObjectType());
		//Save ourselves a trip through the loop below if there are no restricted fields
		if(restrictedFields == null && restrictedFields.isEmpty())
			return;

		Map<String,Object> fieldsMap = getFieldMapFromExistingSObject(obj);
		
		// If any restricted fields are present, throw an exception
		for(String fieldName : restrictedFields){
			if(fieldsMap.get(fieldName) != null){ // if any of the restricted fields are present in the candidate, throw an exception
				throw new FLSException(obj.getSObjectType(),obj.getSObjectType().getDescribe().fields.getMap().get(fieldName),Operation.OP_INSERT);
			}
		}  
	}

	private static void checkUpdateAction(SObject obj, SObject existingRecord){
		List<String> restrictedFields = cachedRestrictedFields.get(Operation.OP_UPDATE).get(obj.getSObjectType());
		//Save ourselves a trip through the loop below if there are no restricted fields
		if(restrictedFields == null && restrictedFields.isEmpty())
			return;

		Map<String,Object> fieldsMap = getFieldMapFromExistingSObject(obj);
		
		// If any of the restricted values are present and have changed in the dml candidate object, throw an exception
		for(String fieldName : restrictedFields){
			if(fieldsMap.get(fieldName) != null && fieldsMap.get(fieldName) != existingRecord.get(fieldName) ){
				throw new FLSException(obj.getSObjectType(),obj.getSObjectType().getDescribe().fields.getMap().get(fieldName),Operation.OP_UPDATE);
			}
		}	 
	}


	// For update and upsert operations, retrieve a Map of all existing records, for each object that has an ID.
	// objects without an Id are skipped, because there is no existing record in the database.
	private static Map<Id,SObject> getExistingRecords(Map<SObjectType,List<Id>> objTypeMap){
		Map<ID, SObject> result = new Map<Id,SObject>();

		Map<SObjectType,List<String>> operationRestrictedFields = cachedRestrictedFields.get(Operation.OP_UPDATE);
		
		for(SObjectType objType : objTypeMap.keySet()){
			List<String> restrictedFields = operationRestrictedFields.get(objType);
			
			if(restrictedFields == null || restrictedFields.isEmpty()){
				continue;
			}

			List<Id> seenIds = objTypeMap.get(objType);
			if(seenIds.isEmpty()){
				continue;
			}

			String fieldList = String.join(restrictedFields,',');
			result.putAll((Database.query('SELECT ' + fieldList + ' FROM ' + objType.getDescribe().getName() + ' WHERE Id IN :seenIds')));
		}
		
		return result;
	}
		
	// Check CRUD permissions for the current user on the object
	private static void checkCRUDPermission(Set<SObjectType> objTypeList, Operation dmlOperation){
		for(SObjectType objType : objTypeList){
			DescribeSObjectResult describeObject = objType.getDescribe();
			if((dmlOperation == Operation.OP_INSERT && !describeObject.isCreateable()) ||
				(dmlOperation == Operation.OP_UPDATE && !describeObject.isUpdateable()) ||
				(dmlOperation == Operation.OP_DELETE && !describeObject.isDeletable()) ||
				(dmlOperation == Operation.OP_UPSERT && !(describeObject.isCreateable() && describeObject.isUpdateable()))) {
				throw new CRUDException(objType,dmlOperation);
			}
		}
	}
	
	// Get a Map of all the object types in the dml request and the list of fields for each 
	// that the current user cannot update, based on FLS security settings
	private static Map<SObjectType,List<Id>> analyzeDMLCollection(List<SObject> objList, Operation dmlOperation){
		Map<SObjectType,List<Id>> result = new Map<SObjectType,List<Id>>();
		
		for(SObject obj : objList){
			ensureRestrictedFieldsEntry(obj, dmlOperation);
		
			List<Id> seenIds = result.get(obj.getSObjectType());
			if(seenIds == null){
				seenIds = new List<Id>();
				result.put(obj.getSObjectType(),seenIds);
			}
			
			if(obj.Id == null){
				continue;
			}	
			
			seenIds.add(obj.Id);
			
		}
		return result;
	}
	
	private static void ensureRestrictedFieldsEntry(SObject obj, Operation dmlOperation){
		if(dmlOperation == Operation.OP_UPSERT){
			ensureRestrictedFields(obj,Operation.OP_INSERT);
			ensureRestrictedFields(obj,Operation.OP_UPDATE);
		}
		else{
			ensureRestrictedFields(obj,dmlOperation);
		}
	}
	
	private static void ensureRestrictedFields(SObject obj, Operation dmlOperation){
		Map<SObjectType,List<String>> operationRestrictedFields = cachedRestrictedFields.get(dmlOperation);
		if(operationRestrictedFields == null){
			operationRestrictedFields = new Map<SObjectType,List<String>>();
			cachedRestrictedFields.put(dmlOperation,operationRestrictedFields);
		}
		
		if(!operationRestrictedFields.containsKey(obj.getSObjectType())){

			DescribeSObjectResult describeObject = obj.getSObjectType().getDescribe();

			Map<String, Schema.SObjectField> objectFields = describeObject.fields.getMap();

			List<String> restrictedFields = new List<String>();

			for(String nm : objectFields.keyset()){
				if(!exceptionValues.contains(nm.toLowerCase())){
					DescribeFieldResult fr = objectFields.get(nm).getDescribe();
					if((!fr.isCalculated()) && ((dmlOperation == Operation.OP_INSERT && !fr.isCreateable()) ||
					   (dmlOperation == Operation.OP_UPDATE && !fr.isUpdateable())) 
					){
						restrictedFields.add(fr.getName());
					}  // there is not an isDeletable method at the field level
				}
			}
			operationRestrictedFields.put(obj.getSObjectType(),restrictedFields);
		}
	}	

}