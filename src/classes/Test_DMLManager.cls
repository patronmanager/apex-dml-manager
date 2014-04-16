@isTest
private class Test_DMLManager {
	
	static testMethod void flsRestrictedInsert(){
		Campaign c1 = new Campaign(Name = 'Test1 Campaign');
		insert new Campaign[]{c1};
		
		Opportunity o1 = new Opportunity(Name='Original1 Opp',CampaignId=c1.Id,StageName='Won',CloseDate=Date.today());
		
		User newUser = ensureRestrictedUser();
		
		System.runAs(newUser){
			try{
				DMLManager.insertAsUser(new Opportunity[]{o1});
				System.assert(false,'Expected a DML Error! newUser shouldn\'t be able to insert Opportunity.CampaignId');
			}
			catch(DMLManager.FLSException flse){
				//expected
				System.assertEquals(Opportunity.SObjectType,flse.objType);
				System.assertEquals(DMLManager.Operation.OP_INSERT,flse.op);
				System.assertEquals(Opportunity.SObjectType.fields.CampaignId,flse.field);
			}
		}

	}

	static testMethod void flsUnrestrictedUpsert(){
		Campaign c1 = new Campaign(Name = 'Test1 Campaign');
		Campaign c2 = new Campaign(Name = 'Test2 Campaign');
		insert new Campaign[]{c1,c2};
		
		Opportunity o1 = new Opportunity(Name='Original1 Opp',CampaignId=c1.Id,StageName='Won',CloseDate=Date.today());
		DMLManager.upsertAsUser(new Opportunity[]{o1});
		System.assert(o1.Id != null);

		o1.Name='Updated1 Opp';
		o1.CampaignId = c2.Id;
		
		Opportunity o2 = new Opportunity(Name='Test2 Opp',CampaignId=c2.Id,StageName='Won',CloseDate=Date.today());
		
		DMLManager.upsertAsUser(new Opportunity[]{o1,o2});

		List<Opportunity> reload = [SELECT Id, Name, CampaignId FROM Opportunity ORDER BY Id];
		System.assertEquals(reload.size(),2);
		System.assertEquals('Updated1 Opp',reload[0].Name);
		System.assertEquals(c2.Id,reload[0].CampaignId);
		System.assertEquals('Test2 Opp',reload[1].Name);
		System.assertEquals(c2.Id,reload[1].CampaignId);
		System.assert(reload[1].Id != null);
	}

	static testMethod void flsRestrictedUpsert(){
		Campaign c1 = new Campaign(Name = 'Test1 Campaign');
		Campaign c2 = new Campaign(Name = 'Test2 Campaign');
		insert new Campaign[]{c1,c2};
		
		Opportunity o1 = new Opportunity(Name='Original1 Opp',CampaignId=c1.Id,StageName='Won',CloseDate=Date.today());
		insert o1;
		System.assert(o1.Id != null);

		o1.Name='Updated1 Opp';
		o1.CampaignId = c2.Id;
		
		Opportunity o2 = new Opportunity(Name='Test2 Opp',CampaignId=c2.Id,StageName='Won',CloseDate=Date.today());
		
		User newUser = ensureRestrictedUser();
		
		System.runAs(newUser){
			try{
				DMLManager.upsertAsUser(new Opportunity[]{o1,o2});
				System.assert(false,'Expected a DML Error! newUser shouldn\'t be able to update Opportunity.CampaignId');
			}
			catch(DMLManager.FLSException flse){
				//expected
				System.assertEquals(Opportunity.SObjectType,flse.objType);
				System.assertEquals(DMLManager.Operation.OP_UPDATE,flse.op);
				System.assertEquals(Opportunity.SObjectType.fields.CampaignId,flse.field);
			}
		}

	}
	
	//Tests that FLS is enforced even if field is not selected in SOQL query
	static testMethod void flsRestrictedUpdateOfFieldNotSelected(){
		Campaign c1 = new Campaign(Name = 'Test1 Campaign');
		Campaign c2 = new Campaign(Name = 'Test2 Campaign');
		insert new Campaign[]{c1,c2};
		
		Opportunity o1 = new Opportunity(Name='Original1 Opp',CampaignId=c1.Id,StageName='Won',CloseDate=Date.today());
		insert o1;
		System.assert(o1.Id != null);
		
		Opportunity o1Reload = [SELECT Id, Name FROM Opportunity WHERE Id = :o1.Id];
		o1Reload.Name='Updated1 Opp';
		o1Reload.CampaignId = c2.Id;
		
		User newUser = ensureRestrictedUser();
		
		System.runAs(newUser){
			try{
				DMLManager.updateAsUser(new Opportunity[]{o1Reload});
				System.assert(false,'Expected a DML Error! newUser shouldn\'t be able to update Opportunity.CampaignId');
			}
			catch(DMLManager.FLSException flse){
				//expected
				System.assertEquals(Opportunity.SObjectType,flse.objType);
				System.assertEquals(DMLManager.Operation.OP_UPDATE,flse.op);
				System.assertEquals(Opportunity.SObjectType.fields.CampaignId,flse.field);
			}
		}
	}
	
	static testMethod void crudUnrestrictedInsertUpdateDelete(){
		Campaign c1 = new Campaign(Name='Test1 Campaign');
		DMLManager.insertAsUser(c1);

		//Would blow up if the Campaign wasn't inserted (List has no rows for assignment)		
		Campaign c1Reload = [SELECT Id, Name, StartDate FROM Campaign WHERE Id = :c1.Id];
		System.assert(c1Reload.StartDate == null);

		c1Reload.StartDate = Date.today();		 

		DMLManager.updateAsUser(c1Reload);

		c1Reload = [SELECT Id, Name, StartDate FROM Campaign WHERE Id = :c1.Id];
		System.assertEquals(Date.today(),c1Reload.StartDate);
		
		DMLManager.deleteAsUser(c1Reload);

		List<Campaign> reloaded = [SELECT Id, Name FROM Campaign];
		System.assertEquals(0,reloaded.size());
	}

	static testMethod void crudRestrictedInsertUpdateDelete(){
		User newUser = ensureRestrictedUser();

		Campaign c1 = new Campaign(Name='Test1 Campaign');
		insert c1;

      	System.runAs(newUser) {
			// First try to insert a new object (including field two)
			try{
				Campaign c2 = new Campaign(Name='Test2  Campaign');
				DMLManager.insertAsUser(c2);
				System.assert(false,'Expected a DML Error!, newUser shouldn\'t be able to insert a Campaign');
			}
			catch(DMLManager.CRUDException crude){
				//expected
				System.assertEquals(Campaign.SObjectType,crude.objType);
				System.assertEquals(DMLManager.Operation.OP_INSERT,crude.op);
			}

			// Second, try to update the already inserted (previously) object, including field two
			try{
				c1.Name = 'Updated1 Campaign';
				DMLManager.updateAsUser(c1);
				System.assert(false,'Expected a DML Error!, newUser shouldn\'t be able to update a Campaign');
			}
			catch(DMLManager.CRUDException crude){
				//expected
				System.assertEquals(Campaign.SObjectType,crude.objType);
				System.assertEquals(DMLManager.Operation.OP_UPDATE,crude.op);
			}
			
			try{
				DMLManager.deleteAsUser(c1);
				System.assert(false,'Expected a DML Error!, newUser shouldn\'t be able to delete a Campaign');
			}
			catch(DMLManager.CRUDException crude){
				//expected
				System.assertEquals(Campaign.SObjectType,crude.objType);
				System.assertEquals(DMLManager.Operation.OP_DELETE,crude.op);
			}
      	}
	}
	
	private static User ensureRestrictedUser(){
		Profile p = [SELECT Id FROM Profile WHERE Name='Read Only']; 
		
		User newUser = new User(Alias = 'standt', Email='standarduser@testorg.com', 
	      	EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US', 
    	  	LocaleSidKey='en_US', ProfileId = p.Id, 
      		TimeZoneSidKey='America/Los_Angeles', UserName='crudmanageruser1@testorg.com');
      		
      	insert newUser;
      	
      	assignObjectPermission(newUser,'Opportunity',true,true,false);
      	
      	return newUser;
	}
	
	private static void assignObjectPermission(User u, String objectType, Boolean create, Boolean edit, Boolean remove){
      	PermissionSet ps = new PermissionSet(Name = 'Enable' + objectType, Label = 'Enable ' + objectType);
  		insert ps;									
  											
  		ObjectPermissions oPerm = new ObjectPermissions(ParentId = ps.Id,
  			PermissionsRead = true,
  			PermissionsCreate = create,
  			PermissionsEdit = edit,
  			PermissionsDelete = remove,
  			SObjectType = objectType);
  			
  		insert oPerm;									
  					
  		PermissionSetAssignment assign = new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);						
		insert assign;      											
	}
}