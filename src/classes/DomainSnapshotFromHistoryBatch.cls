/**
 * Batch job used to calculate snapshots from history
 */
public class DomainSnapshotFromHistoryBatch implements Database.Batchable<Accounting_Subscription__c>, Database.Stateful {

    private Map<String, Decimal> wamMap;
    private Map<String, Decimal> formsMap;
    private Map<String, Decimal> mobileUsersMap;
    private Map<String, Decimal> recordCountMap;
    private Date currentDate;
    private Date startDate;
    private Boolean error;
    private BatchDefaultSettings__c settings;

    public DomainSnapshotFromHistoryBatch() {
        this(Date.today());
    }

    public DomainSnapshotFromHistoryBatch(Date currentDate) {
        this.currentDate = currentDate;
        this.startDate = this.currentDate.toStartOfMonth();

        this.wamMap = new Map<String, Decimal> { 'Empty' => 0, 'Advanced' => 0, 'Community' => 0, 'Enterprise' => 0, 'Standard' => 0, 'Pro' => 0};
        this.formsMap = new Map<String, Decimal> { 'Empty' => 0, 'Advanced' => 0, 'Community' => 0, 'Enterprise' => 0, 'Standard' => 0, 'Pro' => 0};
        this.mobileUsersMap = new Map<String, Decimal> { 'Empty' => 0, 'Advanced' => 0, 'Community' => 0, 'Enterprise' => 0, 'Standard' => 0, 'Pro' => 0};
        this.recordCountMap = new Map<String, Decimal> { 'Empty' => 0, 'Advanced' => 0, 'Community' => 0, 'Enterprise' => 0, 'Standard' => 0, 'Pro' => 0};
        this.error = false;
        this.settings = BatchDefaultSettings__c.getOrgDefaults();
    }

    public List<Accounting_Subscription__c> start(Database.BatchableContext context) { // We cannot group by formula field
       DateTime dt = DateTime.newInstance(this.currentDate.year(), this.currentDate.month(),this.currentDate.day());
       dt.addDays(1);
       return [SELECT Id, is_active__c, Software_Plan_Edition__c, Accounting_subscriber_domain__r.Wam__c, Accounting_subscriber_domain__r.cpActiveMobileUsers__c, service_type__c,
               Accounting_subscriber_domain__r.cpIsActive__c, Accounting_subscriber_domain__r.cpAllForms__c, Accounting_subscriber_domain__r.InternalProp_self_started__c, Accounting_subscriber_domain__c
               FROM Accounting_Subscription__c
               WHERE is_trial__c = false AND Accounting_subscriber_domain__c != null AND
               Accounting_subscriber_domain__r.is_test__c != 'true' AND CreatedDate <: dt];
    }

    public void execute(Database.BatchableContext context, List<Accounting_Subscription__c> scope) {
        try {
            Map<Id, Boolean> subActiveHistory = getBooleanHistoryValueForField('is_active__c', scope, true);
            Map<Id, Boolean> activeHistory = getBooleanHistoryValueForField('cpIsActive__c', scope, false);

            List<Accounting_Subscription__c> scopeFiltered = new List<Accounting_Subscription__c>();
            for (Accounting_Subscription__c sub : scope) {
                Boolean subActive = sub.is_active__c != null ? sub.is_active__c : false;
                if (subActiveHistory.containsKey(sub.Id)) {
                    subActive = subActiveHistory.get(sub.Id);
                }
                Boolean domCpActive = sub.Accounting_subscriber_domain__r.cpIsActive__c != null ? sub.Accounting_subscriber_domain__r.cpIsActive__c : false;
                if (activeHistory.containsKey(sub.Accounting_subscriber_domain__c)) {
                    domCpActive = activeHistory.get(sub.Accounting_subscriber_domain__c);
                }
                if (subActive == true && domCpActive == true) {
                    scopeFiltered.add(sub);
                }
            }

            Map<Id, Decimal> wamHistory = getHistoryValueForField('Wam__c', scopeFiltered);
            Map<Id, Decimal> formHistory = getHistoryValueForField('cpAllForms__c', scopeFiltered);
            Map<Id, Decimal> activeUsersHistory = getHistoryValueForField('cpActiveMobileUsers__c', scopeFiltered);

            System.debug('wamHistory: ' + wamHistory);
            System.debug('formHistory: ' + formHistory);
            System.debug('activeUsersHistory: ' + activeUsersHistory);

            Integer subs = 0;

            for (Accounting_Subscription__c sub : scopeFiltered) {
                Decimal forms = sub.Accounting_subscriber_domain__r.cpAllForms__c != null ? sub.Accounting_subscriber_domain__r.cpAllForms__c : 0;
                if (formHistory.containsKey(sub.Accounting_subscriber_domain__c)) { // take value from history
                    forms = formHistory.get(sub.Accounting_subscriber_domain__c);
                }

                if (forms >= 300) { // Likely Real simulation
                    subs++;
                    Decimal wam = sub.Accounting_subscriber_domain__r.Wam__c != null ? sub.Accounting_subscriber_domain__r.Wam__c : 0;
                    if (wamHistory.containsKey(sub.Accounting_subscriber_domain__c)) { // take value from history
                        wam = wamHistory.get(sub.Accounting_subscriber_domain__c);
                    }

                    Decimal activeUsers = sub.Accounting_subscriber_domain__r.cpActiveMobileUsers__c != null ? sub.Accounting_subscriber_domain__r.cpActiveMobileUsers__c : 0;
                    if (activeUsersHistory.containsKey(sub.Accounting_subscriber_domain__c)) { // take value from history
                        activeUsers = activeUsersHistory.get(sub.Accounting_subscriber_domain__c);
                    }

                    String softwarePlan = sub.Software_Plan_Edition__c;
                    if (softwarePlan == '' || softwarePlan == null || softwarePlan == '-') {
                        softwarePlan = 'Empty';
                    }

                    this.wamMap.put(softwarePlan, wamMap.get(softwarePlan) + wam);
                    this.formsMap.put(softwarePlan, formsMap.get(softwarePlan) + forms);
                    this.mobileUsersMap.put(softwarePlan, mobileUsersMap.get(softwarePlan) + activeUsers);

                    if ((sub.service_type__c == 'Self_service' || sub.service_type__c == 'Product') && sub.Accounting_subscriber_domain__r.InternalProp_self_started__c == true) {
                        this.recordCountMap.put(softwarePlan, recordCountMap.get(softwarePlan) + 1);
                    }
                }
            }
            System.debug('subs total : ' + subs);
        } catch (Exception e) {
            System.debug('Error: ' + e);
            if (!Test.isRunningTest()) {
                EmailHelper.sendEmailFromException(this.settings.Error_Emails__c.split(','), 'Cannot calculate monthy Domain Snapshots',
                                    'Error : ', e);
            }
            this.error = true;
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            if (error == false) {
                SObject sobj = (SObject) new Domain_Monthly_Snapshot__c();
                sobj = setValues(sobj, wamMap, '_Wam__c');
                sobj = setValues(sobj, formsMap, '_Forms__c');
                sobj = setValues(sobj, mobileUsersMap, '_Active_Mobile_Users__c');
                sobj = setValues(sobj, recordCountMap, '_Scale_of_Programs__c');
                Domain_Monthly_Snapshot__c domainSnapshot = (Domain_Monthly_Snapshot__c) sobj;
                domainSnapshot.Snapshot_Date__c = this.currentDate;
                insert domainSnapshot;
            }
        } catch (Exception e) {
            System.debug('Error: ' + e);
            if (!Test.isRunningTest()) {
                EmailHelper.sendEmailFromException(this.settings.Error_Emails__c.split(','), 'Cannot calculate monthy Domain Snapshots',
                                    'Error : ', e);
            }
        }
    }

    private Map<Id, Decimal> getHistoryValueForField(String fieldName, List<Accounting_Subscription__c> scope) {
        Date beginM = Date.newInstance(this.currentDate.year(), this.currentDate.month(), this.currentDate.day()).addMonths(1).toStartOfMonth();
        DateTime beginMDT = DateTime.newInstance(beginM.year(), beginM.month(),beginM.day());
        DateTime endMDT = DateTime.newInstance(beginM.year(), beginM.month(), Date.daysInMonth(beginM.year(), beginM.month()));

        Set<Id> domainsIds = new Set<Id>();
        for (Accounting_Subscription__c sub : scope) {
            domainsIds.add(sub.Accounting_subscriber_domain__c);
        }

        List<Domain__History> historyRecords = [SELECT ParentId, OldValue, NewValue, CreatedDate FROM Domain__History WHERE ParentId IN: domainsIds AND CreatedDate >=: beginMDT
                                                AND CreatedDate <=: endMDT AND Field =: fieldName ORDER BY CreatedDate ASC];
        Map<Id, Decimal> historyMap = new Map<Id, Decimal>();
        for (Domain__History hrec : historyRecords) {
            if (!historyMap.containsKey((Id) hrec.ParentId)) {
                historyMap.put((Id) hrec.ParentId, hrec.OldValue != null ? (Decimal) hrec.OldValue : 0);
            }
        }

        return historyMap;
    }

    private Map<Id, Boolean> getBooleanHistoryValueForField(String fieldName, List<Accounting_Subscription__c> scope, Boolean forSub) {
        Date beginM = Date.newInstance(this.currentDate.year(), this.currentDate.month(), this.currentDate.day()).addMonths(1).toStartOfMonth();
        DateTime beginMDT = DateTime.newInstance(beginM.year(), beginM.month(),beginM.day());
        DateTime endMDT = DateTime.newInstance(beginM.year(), beginM.month(), Date.daysInMonth(beginM.year(), beginM.month()));

        Map<Id, Boolean> historyMap = new Map<Id, Boolean>();
        if (forSub == true) {
            List<Accounting_Subscription__History> historyRecords = [SELECT ParentId, OldValue, NewValue, CreatedDate FROM Accounting_Subscription__History WHERE ParentId IN: scope AND CreatedDate >=: beginMDT
                                                AND CreatedDate <=: endMDT AND Field =: fieldName ORDER BY CreatedDate ASC];

            for (Accounting_Subscription__History hrec : historyRecords) {
                if (!historyMap.containsKey((Id) hrec.ParentId)) {
                    historyMap.put((Id) hrec.ParentId, hrec.OldValue != null ? (Boolean) hrec.OldValue : false);
                }
            }
        } else {
            Set<Id> domainsIds = new Set<Id>();
            for (Accounting_Subscription__c sub : scope) {
                domainsIds.add(sub.Accounting_subscriber_domain__c);
            }
            List<Domain__History> historyRecords = [SELECT ParentId, OldValue, NewValue, CreatedDate FROM Domain__History WHERE ParentId IN: domainsIds AND CreatedDate >=: beginMDT
                                                AND CreatedDate <=: endMDT AND Field =: fieldName ORDER BY CreatedDate ASC];

            for (Domain__History hrec : historyRecords) {
                if (!historyMap.containsKey((Id) hrec.ParentId)) {
                    historyMap.put((Id) hrec.ParentId, hrec.OldValue != null ? (Boolean) hrec.OldValue : false);
                }
            }
        }

        return historyMap;
    }

    private SObject setValues(SObject obj, Map<String, Decimal> values, String suffix) {

        for (String key : values.keySet()) {
            String name = (key + suffix).toLowerCase();
            Decimal value = values.get(key);
            if (hasSObjectField(name, obj)) {
                obj.put(name, value);
            } else {
                System.debug('Cannot find field with name : ' + name);
                if (!Test.isRunningTest()) {
                    EmailHelper.sendEmail(this.settings.Error_Emails__c.split(','), 'Cannot find sObject field for Domain Monthly Snapshot',
                                    'Cannot find fields: ' + name);
                }
            }
        }
        return obj;
    }

    private Boolean hasSObjectField(String fieldName, SObject so) {
        return so.getSobjectType().getDescribe().fields.getMap().keySet().contains(fieldName);
    }
}