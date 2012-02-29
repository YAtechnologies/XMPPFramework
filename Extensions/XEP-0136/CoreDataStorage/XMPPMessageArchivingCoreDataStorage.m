#import "XMPPMessageArchivingCoreDataStorage.h"
#import "XMPPCoreDataStorageProtected.h"
#import "XMPPLogging.h"
#import "XMPPElement+Delay.h"

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

// Log levels: off, error, warn, info, verbose
// Log flags: trace
#if DEBUG
  static const int xmppLogLevel = XMPP_LOG_LEVEL_VERBOSE; // | XMPP_LOG_FLAG_TRACE;
#else
  static const int xmppLogLevel = XMPP_LOG_LEVEL_WARN;
#endif

@interface XMPPMessageArchivingCoreDataStorage ()
{
	NSString *messageEntityName;
	NSString *contactEntityName;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

@implementation XMPPMessageArchivingCoreDataStorage

static XMPPMessageArchivingCoreDataStorage *sharedInstance;

+ (XMPPMessageArchivingCoreDataStorage *)sharedInstance
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		
		sharedInstance = [[XMPPMessageArchivingCoreDataStorage alloc] initWithDatabaseFilename:nil];
	});
	
	return sharedInstance;
}

/**
 * Documentation from the superclass (XMPPCoreDataStorage):
 * 
 * If your subclass needs to do anything for init, it can do so easily by overriding this method.
 * All public init methods will invoke this method at the end of their implementation.
 * 
 * Important: If overriden you must invoke [super commonInit] at some point.
**/
- (void)commonInit
{
	[super commonInit];
	
	messageEntityName = @"XMPPMessageArchiving_Message_CoreDataObject";
	contactEntityName = @"XMPPMessageArchiving_Contact_CoreDataObject";
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Internal API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (XMPPMessageArchiving_Contact_CoreDataObject *)contactWithBareJidStr:(NSString *)bareJidStr
                                                      streamBareJidStr:(NSString *)streamBareJidStr
{
	NSManagedObjectContext *moc = [self managedObjectContext];
	NSEntityDescription *entity = [self contactEntity:moc];
	
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"bareJidStr == %@ AND streamBareJidStr == %@",
	                                                              bareJidStr, streamBareJidStr];
	
	NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
	[fetchRequest setEntity:entity];
	[fetchRequest setFetchLimit:1];
	[fetchRequest setPredicate:predicate];
	
	NSError *error = nil;
	NSArray *results = [moc executeFetchRequest:fetchRequest error:&error];
	
	if (results == nil)
	{
		XMPPLogError(@"%@: %@ - Fetch request error: %@", THIS_FILE, THIS_METHOD, error);
		return nil;
	}
	else
	{
		return (XMPPMessageArchiving_Contact_CoreDataObject *)[results lastObject];
	}
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Public API
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (NSString *)messageEntityName
{
	__block NSString *result = nil;
	
	dispatch_block_t block = ^{
		result = messageEntityName;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_sync(storageQueue, block);
	
	return result;
}

- (void)setMessageEntityName:(NSString *)entityName
{
	dispatch_block_t block = ^{
		messageEntityName = entityName;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_async(storageQueue, block);
}

- (NSString *)contactEntityName
{
	__block NSString *result = nil;
	
	dispatch_block_t block = ^{
		result = contactEntityName;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_sync(storageQueue, block);
	
	return result;
}

- (void)setContactEntityName:(NSString *)entityName
{
	dispatch_block_t block = ^{
		contactEntityName = entityName;
	};
	
	if (dispatch_get_current_queue() == storageQueue)
		block();
	else
		dispatch_async(storageQueue, block);
}

- (NSEntityDescription *)messageEntity:(NSManagedObjectContext *)moc
{
	// This is a public method, and may be invoked on any queue.
	// So be sure to go through the public accessor for the entity name.
	
	return [NSEntityDescription entityForName:[self messageEntityName] inManagedObjectContext:moc];
}

- (NSEntityDescription *)contactEntity:(NSManagedObjectContext *)moc
{
	// This is a public method, and may be invoked on any queue.
	// So be sure to go through the public accessor for the entity name.
	
	return [NSEntityDescription entityForName:[self contactEntityName] inManagedObjectContext:moc];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark Storage Protocol
////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

- (BOOL)configureWithParent:(XMPPMessageArchiving *)aParent queue:(dispatch_queue_t)queue
{
	return [super configureWithParent:aParent queue:queue];
}

- (void)archiveMessage:(XMPPMessage *)message outgoing:(BOOL)isOutgoing xmppStream:(XMPPStream *)xmppStream
{
	NSString *messageBody = [[message elementForName:@"body"] stringValue];
	
	if ([messageBody length] == 0)
	{
		return;
	}
	
	[self scheduleBlock:^{
		
		NSManagedObjectContext *moc = [self managedObjectContext];
		
		// Insert new message
		
		XMPPMessageArchiving_Message_CoreDataObject *archivedMessage = (XMPPMessageArchiving_Message_CoreDataObject *)
		    [[NSManagedObject alloc] initWithEntity:[self messageEntity:moc] insertIntoManagedObjectContext:nil];
		
		archivedMessage.message = message;
		archivedMessage.body = messageBody;
		
		NSDate *timestamp = [message delayedDeliveryDate];
		if (timestamp)
			archivedMessage.timestamp = timestamp;
		else
			archivedMessage.timestamp = [[NSDate alloc] init];
		
		if (isOutgoing)
			archivedMessage.bareJid = [[message to] bareJID];
		else
			archivedMessage.bareJid = [[message from] bareJID];
		
		archivedMessage.thread = [[message elementForName:@"thread"] stringValue];
		archivedMessage.isOutgoing = isOutgoing;
		
		archivedMessage.streamBareJidStr = [[self myJIDForXMPPStream:xmppStream] bare];
		
		[archivedMessage willInsertObject]; // Override hook
		[moc insertObject:archivedMessage];
		
		// Create or update contact
		
		XMPPMessageArchiving_Contact_CoreDataObject *contact =
		    [self contactWithBareJidStr:archivedMessage.bareJidStr streamBareJidStr:archivedMessage.streamBareJidStr];
		
		if (contact == nil)
		{
			contact = (XMPPMessageArchiving_Contact_CoreDataObject *)
			    [[NSManagedObject alloc] initWithEntity:[self contactEntity:moc] insertIntoManagedObjectContext:nil];
			
			contact.streamBareJidStr = archivedMessage.streamBareJidStr;
			contact.bareJid = archivedMessage.bareJid;
			
			contact.mostRecentMessageTimestamp = [[NSDate alloc] init];
			contact.mostRecentMessageBody = archivedMessage.body;
			contact.mostRecentMessageOutgoing = [NSNumber numberWithBool:isOutgoing];
			
			[contact willInsertObject]; // Override hook
			[moc insertObject:contact];
		}
		else
		{
			contact.mostRecentMessageTimestamp = [[NSDate alloc] init];
			contact.mostRecentMessageBody = archivedMessage.body;
			contact.mostRecentMessageOutgoing = [NSNumber numberWithBool:isOutgoing];
			
			[contact didUpdateObject];  // Override hook
		}
	}];
}

@end