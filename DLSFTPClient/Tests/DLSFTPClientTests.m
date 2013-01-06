//
//  DLSFTPClientTests.m
//  DLSFTPClientTests
//
//  Created by Dan Leehr on 1/6/13.
//  Copyright (c) 2013 Dan Leehr. All rights reserved.
//

#import "DLSFTPClientTests.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "NSDictionary+SFTPFileAttributes.h"

@interface DLSFTPClientTests ()

@property (strong, nonatomic) NSConditionLock *conditionLock;

@end


@implementation DLSFTPClientTests

- (void)setUp {
    [super setUp];
}

- (void)tearDown
{
    // Tear-down code here.
    [super tearDown];
}

- (void)testConnect {

    static NSString *hostname = @"hostname";
    static NSString *username = @"username";
    static NSString *password = @"password";
    static NSUInteger port = 22;
    __block NSError *localError = nil;

    self.conditionLock = [NSConditionLock new];
    
    DLSFTPConnection *connection = [[DLSFTPConnection alloc] initWithHostname:hostname
                                                                         port:port
                                                                     username:username
                                                                     password:password];
    STAssertNotNil(connection, @"Connection is nil");
    __weak DLSFTPClientTests *weakSelf = self;
    [connection connectWithSuccessBlock:^{
        [weakSelf.conditionLock unlockWithCondition:1];
    } failureBlock:^(NSError *error) {
        localError = error;
        [weakSelf.conditionLock unlockWithCondition:1];
    }];
    [weakSelf.conditionLock lockWhenCondition:1];


    // must have succeeded without error
    STAssertNil(localError, localError.localizedDescription);

    STAssertTrue([connection isConnected], @"Connection unsuccessful");
    // now disconnect
    [connection disconnect];

    STAssertFalse([connection isConnected], @"Disconnection unsuccessful");
}
/*
- (void)testList {
    STFail(@"Not yet implemented");
}

- (void)testChDir {
    STFail(@"Not yet implemented");
}

- (void)testDownload {
    STFail(@"Not yet implemented");    
}

- (void)testUpload {
    STFail(@"Not yet implemented");
}

- (void)testUploadAndDownload {
    STFail(@"Not yet implemented");
}
*/
// what else to test.  Concurrency - download and list


@end
