void captureWebDeepLinkForSession() {}

(String?, String?) readDeepLinkIdsFromUrlOrHash() => (null, null);

String? readSubtaskIdFromUrlOrSession() => null;

String? readTaskIdFromUrlOrSession() => null;

void consumeSubtaskDeepLink() {}

void consumeTaskDeepLink() {}

void clearDeepLinkQueryFromAddressBar() {}

void syncWebLocationForTaskDetail(String taskId) {}

void clearWebTaskDetailFromLocation() {}

void syncWebLocationForSubtaskDetail(String subtaskId) {}

void clearWebSubtaskDetailFromLocation({String? parentTaskId}) {}

void syncWebLocationForLanding() {}
