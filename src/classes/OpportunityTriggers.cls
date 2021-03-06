/**
 * Logic for the different triggers defined on Opportunities
 *
 * @author  Antonio Grassi
 * @date    11/13/2012
 */
public with sharing class OpportunityTriggers {

    private static final Set<String> PRODUCTS_AS_TAGS = new Set<String>{'CommCare', 'CommConnect', 'CommTrack'};

    public static void updateDomainAccountRelation(List<Opportunity> oppsNew, Map<Id, Opportunity> oldOppsMap) {
        Set<Id> oppsWithUpdatedAccount = new Set<Id>();
        Map<Id, Id> oppToAccountMap = new Map<Id, Id>();

        for (Opportunity newOpp : oppsNew) {
            Opportunity oldOpp = oldOppsMap.get(newOpp.Id);
            if (newOpp.AccountId != null && newOpp.AccountId != oldOpp.AccountId) {
                oppsWithUpdatedAccount.add(newOpp.Id);
                oppToAccountMap.put(newOpp.Id, newOpp.AccountId);
            }
        }

        if (oppsWithUpdatedAccount.size() > 0) {
            List<Domain__c> domainsToUpdate = new List<Domain__c>();
            List<Domain__c> domains = [SELECT Id, Name, Account__c, Opportunity__c FROM Domain__c WHERE Opportunity__c IN: oppsWithUpdatedAccount];
            for (Domain__c domain : domains) {
                Id accountId = oppToAccountMap.get(domain.Opportunity__c);
                if (accountId != null) {
                    domain.Account__c = accountId;
                    domainsToUpdate.add(domain);
                }
            }
            if (domainsToUpdate.size() > 0) {
                update domainsToUpdate;
            }
        }
    }

    /**
     * We use @future here in order to perform HTTP callouts from within a trigger context
     */
    @future(callout=true)
    public static void createInFogbugz(Id opportunityId) {
        Opportunity o = FogBugzUtils.fetchOpportunity(opportunityId);

        if (o != null) {
            FogBugzCase fbCase = FogBugzUtils.createFBCaseFromOpportunity(o);
            FogBugzAPI fbAPI = new FogBugzAPI();

            Boolean close = o.IsClosed;
            String fbCaseId = !Test.isRunningTest() ? fbAPI.createCase(fbCase, close) : (o.Fogbugz_Ticket_Number__c != FogBugzHttpCalloutMock.EMPTY_ID ? FogBugzHttpCalloutMock.TEST_FB_ID : FogBugzHttpCalloutMock.EMPTY_ID);

            if (fbCaseId != null) {
                o.Fogbugz_Ticket_Number__c = fbCaseId;
                update o;
            } else {
                System.debug(LoggingLevel.ERROR, 'OpportunityTriggers::createInFogbugz() - Error while creating case');
            }
        } else {
            System.debug(LoggingLevel.WARN, 'OpportunityTriggers::createInFogbugz() - Could not find opportunity just created (???)');
        }
    }

     /**
     * We use @future here in order to perform HTTP callouts from within a trigger context
     */
    @future(callout=true)
    public static void closeFogbugzCase(String ticket_number) {
        if (ticket_number != null) {
            FogBugzAPI fbAPI = new FogBugzAPI();
            FogBugzCase fbCase = fbAPI.getCase(ticket_number);
            String fbCaseId = fbAPI.resolveCase(fbCase);
            if (fbCaseId != null) {
                fbCaseId = fbAPI.closeCase(fbCase);
            }
        }
    }

    public static void updateCaseInFogbugz(Opportunity oppNew, Opportunity oppOld) {
        if ((oppNew.Name != oppOld.Name) ||
            (oppNew.StageName != oppOld.StageName) ||
            (oppOld.Fogbugz_Probability__c != oppNew.Fogbugz_Probability__c) ||
            (oppOld.Product_Text__c != oppNew.Product_Text__c) ||
            (oppOld.Amount != oppNew.Amount)) {

            if (!System.isBatch()) {
                FogBugzCase fbCase = FogBugzUtils.createFBCaseFromOpportunity(oppNew);
                String tags = null;
                Boolean editTags = (oppOld.Fogbugz_Probability__c != oppNew.Fogbugz_Probability__c) ||
                                       (oppNew.Product_Text__c != oppOld.Product_Text__c);
                updateCase(oppNew.Id, editTags, oppNew.Product_Text__c, oppOld.Product_Text__c, oppOld.StageName);
            }
        }
    }

    /**
     * We use @future here in order to perform HTTP callouts from within a trigger context
     */
    @future(callout=true)
    public static void updateCase(String opportunityId, boolean editTags, String oldProds, String newProds, String oldStage) {
        System.debug('Update Case future method: ');
        Opportunity o = FogBugzUtils.fetchOpportunity(opportunityId);

        if (o != null) {
            FogBugzCase fbCase = FogBugzUtils.createFBCaseFromOpportunity(o);
            FogBugzAPI fbAPI = new FogBugzAPI();

            if (o.Amount != null) {
                fbCase.dealSize = o.Amount.intValue();
            } else {
                fbCase.dealSize = 0;
            }

            if (fbCase.probability != null) {
                fbCase.probability = o.Fogbugz_Probability__c;
            } else {
                fbCase.probability = 0;
            }

            Set<String> tags = new Set<String>();

            if (((oldProds != null) && !oldProds.equals(newProds)) || ((newProds != null) && (!newProds.equals(oldProds)))) {
                Set<String> oldProducts = new Set<String>();
                if (oldProds != null) {
                    oldProducts.addAll(oldProds.split('; '));
                }

                Set<String> newProducts = new Set<String>();
                if (newProds != null) {
                    newProducts.addAll(newProds.split('; '));
                }

                if (newProducts.size() >= oldProducts.size()) {
                    for (String newProd : newProducts) {
                        if ((PRODUCTS_AS_TAGS.contains(newProd)) && (!oldProducts.contains(newProd))) {
                            tags.add(newProd);
                        }
                    }
                } else {
                    for (String oldProd : oldProducts) {
                        if ((PRODUCTS_AS_TAGS.contains(oldProd)) && (!newProducts.contains(oldProd))) {
                            tags.add(oldProd);
                        }
                    }
                }
            }

            Boolean close = o.IsClosed;
            Boolean reopen = FogBugzUtils.closedStages.contains(oldStage) && (!o.StageName.equals(oldStage));
            System.debug('Case - Opp: ' + opportunityId + ' tags: ' + editTags + ' close: ' + close + 'reopen: ' + reopen);
            System.debug('Case - old stage: ' + oldStage + ' new stage: ' + o.StageName);
            String fbCaseId = !Test.isRunningTest() ? fbAPI.updateCaseTitleStageTag(fbCase, editTags, tags, close, reopen) : FogBugzHttpCalloutMock.EMPTY_ID;
        } else {
            System.debug(LoggingLevel.WARN, 'OpportunityTriggers::updateCase() - Could not find opportunity just created (???)');
        }
    }
}