void captureWebDeepLinkForSession({bool clearStaleWhenUrlEmpty = true}) {}

(String?, String?) readDeepLinkIdsFromUrlOrHash() => (null, null);

String? readSubtaskIdFromUrlOrSession() => null;

String? readTaskIdFromUrlOrSession() => null;

String? readProjectIdFromUrlOrSession() => null;

String? readDashboardViewFromUrlOrSession() => null;

void consumeSubtaskDeepLink() {}

void consumeTaskDeepLink() {}

void clearDeepLinkQueryFromAddressBar() {}

void syncWebLocationForTaskDetail(String taskId) {}

void clearWebTaskDetailFromLocation() {}

void syncWebLocationForSubtaskDetail(String subtaskId) {}

void clearWebSubtaskDetailFromLocation({String? parentTaskId}) {}

void syncWebLocationForProjectDetail(String projectId) {}

void clearWebProjectDetailFromLocation() {}

void syncWebLocationForDefaultHome() {}

void syncWebLocationForOverviewDashboard() {}

void syncWebLocationForProjectDashboard() {}

void syncWebLocationForLanding() {}

void syncWebStaleDetailSessionsIfUrlHasNoTaskOrSubtask() {}
