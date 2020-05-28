/**
* Copyright (c), PatronManager LLC
* All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification,
*   are permitted provided that the following conditions are met:
*
* - Redistributions of source code must retain the above copyright notice,
*      this list of conditions and the following disclaimer.
* - Redistributions in binary form must reproduce the above copyright notice,
*      this list of conditions and the following disclaimer in the documentation
*      and/or other materials provided with the distribution.
* - Neither the name of the Patron Holdings nor the names of its contributors
*      may be used to endorse or promote products derived from this software without specific prior written permission.
*
*  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
*  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
*  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
*  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
*  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
*  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
*  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
*  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

@isTest
private class Test_DMLManager {
	
	static testMethod void systemInsert(){
		Opportunity o1 = new Opportunity(Name='Original1 Opp',StageName='Won',CloseDate=Date.today());
		
		User newUser = ensureRestrictedUser();
		
		System.runAs(newUser){
			DMLManager.insertAsSystem(new Opportunity[]{o1});
		}
	}

	static testMethod void systemUpdate(){
		Account a1 = new Account(Name='Apple Account');

		System.runAs(new User(Id = UserInfo.getUserId())){
			insert a1;
		}
		
		User newUser = ensureRestrictedUser();
		
		System.runAs(newUser){
			a1.Name = 'Apple Updated';
			DMLManager.updateAsSystem(new Account[]{a1});
			Account a1Reload = [SELECT Name FROM Account WHERE Id = :a1.Id];
			System.assertEquals('Apple Updated', a1Reload.Name);
		}
	}
	
	static testMethod void systemUpsert(){
		Account a1 = new Account(Name='Apple Account');

		System.runAs(new User(Id = UserInfo.getUserId())){
			insert a1;
		}
		
		Account a1Clone = new Account(Id = a1.Id, Name= 'Apple Updated');
		
		User newUser = ensureRestrictedUser();
		
		System.runAs(newUser){
			DMLManager.upsertAsSystem(new Account[]{a1Clone});
			Account a1Reload = [SELECT Name FROM Account WHERE Id = :a1.Id];
			System.assertEquals('Apple Updated', a1Reload.Name);
		}
	}

	static testMethod void systemDelete(){
		User newUser = ensureRestrictedUser();

		System.runAs(newUser){
			Account a1 = new Account(Name='Apple Account');
			insert a1;
			DMLManager.deleteAsSystem(new Account[]{a1});
		}
	}
	
	@IsTest
	static void mergeAsSystem_Expect_Success(){
		// Insert a master account and two merge accounts
		List<Account> accList = new List<Account>{
			new Account(Name = 'Master Account'),
			new Account(Name = 'Merge One'),
			new Account(Name = 'Merge Two')
		
		};
		
		User newUser = ensureRestrictedUser();
		
		System.runAs(newUser){
			insert accList;
			
			Account masterAcct = [SELECT Id, Name FROM Account WHERE Name = 'Master Account'];
			List<Account> mergeList = [SELECT Id, Name FROM Account WHERE Name LIKE 'Merge%'];
			System.assertEquals(2, mergeList.size());
			
			DMLManager.mergeAsSystem(masterAcct, mergeList);
		}
		
		// Make sure 'Master Account' is still there.
		Account masterAcct = [SELECT Id FROM Account WHERE Name = 'Master Account'];
		
		//Make sure merge accounts are gone
		List<Account> mergeList = [SELECT Id FROM Account WHERE Name LIKE 'Merge%'];
		System.assertEquals(0, mergeList.size());
	
	}
	
	static testMethod void flsRestrictedInsert(){
		Campaign c1 = new Campaign(Name = 'Test1 Campaign');
		System.runAs(new User(Id = UserInfo.getUserId())){
			insert new Campaign[]{c1};
		}
		
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
		System.runAs(new User(Id = UserInfo.getUserId())){
			insert new Campaign[]{c1,c2};
		}
		
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
		Opportunity o1 = new Opportunity(Name='Original1 Opp',CampaignId=c1.Id,StageName='Won',CloseDate=Date.today());

		System.runAs(new User(Id = UserInfo.getUserId())){
			insert new SObject[]{c1,c2,o1};
		}
		
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
		Opportunity o1 = new Opportunity(Name='Original1 Opp',CampaignId=c1.Id,StageName='Won',CloseDate=Date.today());

		System.runAs(new User(Id = UserInfo.getUserId())){
			insert new SObject[]{c1,c2,o1};
		}
		
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
		System.runAs(new User(Id = UserInfo.getUserId())){
			insert c1;
		}

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
	
	@IsTest
	static void mergeAsUser_When_UserHasCorrectPermissions_Expect_Success(){
		// Insert a master account and two merge accounts
		List<Account> accList = new List<Account>{
			new Account(Name = 'Master Account'),
			new Account(Name = 'Merge One'),
			new Account(Name = 'Merge Two')
		};
		
		User newUser = ensureRestrictedUser();
		//Assign read, update & delete permissions to the Account
		assignObjectPermission(newUser,'Account',false,true,true);
		
		System.runAs(newUser){
			insert accList;
			
			Account masterAcct = [SELECT Id, Name FROM Account WHERE Name = 'Master Account'];
			List<Account> mergeList = [SELECT Id, Name FROM Account WHERE Name LIKE 'Merge%'];
			System.assertEquals(2, mergeList.size());
			
			DMLManager.mergeAsUser(masterAcct, mergeList);
		}
		
		// Make sure 'Master Account' is still there.
		Account masterAcct = [SELECT Id FROM Account WHERE Name = 'Master Account'];
		
		//Make sure merge accounts are gone
		List<Account> mergeList = [SELECT Id FROM Account WHERE Name LIKE 'Merge%'];
		System.assertEquals(0, mergeList.size());
	
	}
	
	@IsTest
	static void mergeAsUser_When_UserDoesNotHaveEditPermission_Expect_Error(){
		// Insert a master account and two merge accounts
		List<Account> accList = new List<Account>{
			new Account(Name = 'Master Account'),
			new Account(Name = 'Merge One'),
			new Account(Name = 'Merge Two')
		};
		
		User newUser = ensureRestrictedUser();
		//Assign permissions to the Account but not edit (delete depends on edit so needs to be false too)
		assignObjectPermission(newUser,'Account',true,false,false);
		
		System.runAs(newUser){
			insert accList;
			
			Account masterAcct = [SELECT Id, Name FROM Account WHERE Name = 'Master Account'];
			List<Account> mergeList = [SELECT Id, Name FROM Account WHERE Name LIKE 'Merge%'];
			System.assertEquals(2, mergeList.size());
			
			try {
				DMLManager.mergeAsUser(masterAcct, mergeList);
				System.assert(false,'Expected a DML Error, newUser shouldn\'t be able to merge Account because they don\'t have EDIT permission');
			} catch (DMLManager.CRUDException crudex){
				//expected
				System.assertEquals(Account.SObjectType,crudex.objType);
				System.assertEquals(DMLManager.Operation.OP_UPDATE,crudex.op);
			}
		}
		
		// 'Master Account' and merge accounts should still be there.
		accList = [SELECT Id FROM Account];
		System.assertEquals(3, accList.size());
	
	}
	
	@IsTest
	static void mergeAsUser_When_UserDoesNotHaveDeletePermission_Expect_Error(){
		// Insert a master account and two merge accounts
		List<Account> accList = new List<Account>{
			new Account(Name = 'Master Account'),
			new Account(Name = 'Merge One'),
			new Account(Name = 'Merge Two')
		};
		
		User newUser = ensureRestrictedUser();
		//Assign permissions to the Account but not 'Delete'
		assignObjectPermission(newUser,'Account',true,true,false);
		
		System.runAs(newUser){
			insert accList;
			
			Account masterAcct = [SELECT Id, Name FROM Account WHERE Name = 'Master Account'];
			List<Account> mergeList = [SELECT Id, Name FROM Account WHERE Name LIKE 'Merge%'];
			System.assertEquals(2, mergeList.size());
			
			try {
				DMLManager.mergeAsUser(masterAcct, mergeList);
				System.assert(false,'Expected a DML Error, newUser shouldn\'t be able to merge Account because they don\'t have DELETE permission');
			} catch (DMLManager.CRUDException crudex){
				//expected
				System.assertEquals(Account.SObjectType,crudex.objType);
				System.assertEquals(DMLManager.Operation.OP_DELETE,crudex.op);
			}
		}
		
		// 'Master Account' and merge accounts should still be there.
		accList = [SELECT Id FROM Account];
		System.assertEquals(3, accList.size());
	
	}
	
	static testmethod void testFailedUpdateWithErroneousId(){
		Campaign c1 = new Campaign(Name = 'Test1 Campaign');
		Id cId = null;
	
		insert new SObject[]{c1};
		cId = c1.Id;
		delete c1;
		
		try{
			Campaign c1Resurrected = new Campaign(Id = cId, Name = 'Resurrected Campaign');
			DMLManager.upsertAsUser(c1Resurrected);
			System.assert(false,'Expected a DMLManagerException! Attempting to update a record with an erroneous Id should fail');
		}
		catch(DMLManager.DMLManagerException dmle){
			//expected
			System.assert(dmle.getMessage().contains('An existing record could not be found'));
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