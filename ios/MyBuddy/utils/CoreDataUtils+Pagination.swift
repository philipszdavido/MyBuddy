//
//  CoreDataUtils+Pagination.swift
//

import Foundation
import CoreData

extension CoreDataUtils {
    /// Timestamp of the oldest cached message in a chat; the cursor for loading older history.
    @MainActor
    func oldestMessageDate(chatId: String) -> Date? {
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "chatId == %@ AND sent == YES", chatId)
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
        request.fetchLimit = 1
        return (try? managedObjectContext.fetch(request))?.first?.timestamp
    }
}
