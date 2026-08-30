import BackgroundTasks
import Foundation

enum BackgroundRefreshManager {
    static let identifier = "com.xuwenxu.tokenplan.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            schedule()
            let operation = Task { @MainActor in
                let model = AppModel()
                await model.refreshAll()
                refreshTask.setTaskCompleted(success: true)
            }
            refreshTask.expirationHandler = {
                operation.cancel()
                refreshTask.setTaskCompleted(success: false)
            }
        }
    }

    static func schedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
