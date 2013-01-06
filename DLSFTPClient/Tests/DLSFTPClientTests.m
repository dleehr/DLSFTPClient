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

@property (strong, nonatomic) NSDictionary *connectionInfo;

@end


@implementation DLSFTPClientTests

- (void)setUp {
    [super setUp];
    NSString *connectionInfoPath = [[NSBundle bundleWithIdentifier:@"com.hammockdistrict.DLSFTPClientTests"] pathForResource:@"ConnectionInfo"
                                                                                                                      ofType:@"plist"];
    self.connectionInfo = [NSDictionary dictionaryWithContentsOfFile:connectionInfoPath];

}

- (void)tearDown
{
    // Tear-down code here.
    [super tearDown];
}

- (void)testConnect {

    __block NSError *localError = nil;
    
    DLSFTPConnection *connection = [[DLSFTPConnection alloc] initWithHostname:self.connectionInfo[@"hostname"]
                                                                         port:[self.connectionInfo[@"port"] integerValue]
                                                                     username:self.connectionInfo[@"username"]
                                                                     password:self.connectionInfo[@"password"]
                                    ];
    STAssertNotNil(connection, @"Connection is nil");
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [connection connectWithSuccessBlock:^{
        dispatch_semaphore_signal(semaphore);
    } failureBlock:^(NSError *error) {
        localError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

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
