/**
 *
 * @author  Fernando Rodriguez (frodriguez@adooxen.com)
 * @date    01/11/2012
 *
 */
global class OpenOpportunitiesBatch implements Database.Batchable<sObject> {

    public OpenOpportunitiesBatch() {}

    global Iterable<sObject> start(Database.BatchableContext bc) {
        Opportunity [] opportunities = new Opportunity [] {};
        opportunities = [SELECT Id, OwnerId FROM Opportunity WHERE Isclosed = false];

        Set<Id> usersId = new Set<Id>();
        for(Opportunity opp :opportunities) {
            usersId.add(opp.OwnerId);
        }

        User[] users = [SELECT Id, Email, Name FROM User WHERE Id IN :usersId];
        return users;
    }

    global void execute(Database.BatchableContext bc, User[] scope) {
        User user = scope[0];
        List<String> channel = OpenOpportunityReportController.getInstance().getChannelListForQuery();
        Map<String, Opportunity[]> stagedOpportunities = OpenOpportunityReportController.getInstance().getOpenOpportunitiesOrderByStage(user.Id, channel);

        OpenOpportunityMailer.sendOpenOpportunitiesBatchReport(user, new String[]{user.Email}, stagedOpportunities);
    }

    global void finish(Database.BatchableContext bc) {}
}