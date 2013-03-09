//
//  DLSFTPClientPrivateKeyTests.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 2/12/13.
//  Copyright (c) 2013 Dan Leehr. All rights reserved.
//

#import "DLSFTPClientPrivateKeyTests.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "DLSFTPListFilesRequest.h"

#import "NSDictionary+SFTPFileAttributes.h"

@interface DLSFTPClientPrivateKeyTests ()

@property (strong, nonatomic) NSDictionary *connectionInfo;
@property (strong, nonatomic) DLSFTPConnection *connection;
@property (strong, nonatomic) NSString *testFilePath;

@end

@implementation DLSFTPClientPrivateKeyTests
- (void)setUp {
    [super setUp];

    NSString *privateKeyPath =  [[NSBundle bundleWithIdentifier:@"com.hammockdistrict.DLSFTPClientTests"] pathForResource:@"privatekey"
                                                                                                                   ofType:@"pem"];
    STAssertNotNil(privateKeyPath, @"Please add a private key to DLSFTPClient/DLSFTPClient/Tests as privatekey.pem");

    NSString *connectionInfoPath = [[NSBundle bundleWithIdentifier:@"com.hammockdistrict.DLSFTPClientTests"] pathForResource:@"ConnectionInfo"
                                                                                                                      ofType:@"plist"];
    STAssertNotNil(connectionInfoPath, @"Please add ConnectionInfo.plist to DLSFTPClient/DLSFTPClient/Tests (Copy the ConnectionInfo-template.plist and add your own SFTP host info");
    self.connectionInfo = [NSDictionary dictionaryWithContentsOfFile:connectionInfoPath];
    DLSFTPConnection *connection = [[DLSFTPConnection alloc] initWithHostname:self.connectionInfo[@"hostname"]
                                                                         port:[self.connectionInfo[@"port"] integerValue]
                                                                     username:self.connectionInfo[@"username"]
                                                                      keypath:privateKeyPath
                                                                   passphrase:self.connectionInfo[@"passphrase"]];
    self.connection = connection;
    STAssertNotNil(self.connection, @"Connection is nil");

    NSString *testFilePath = [[NSBundle bundleWithIdentifier:@"com.hammockdistrict.DLSFTPClientTests"] pathForResource:@"testfile"
                                                                                                                ofType:@"jpg"];
    self.testFilePath = testFilePath;
    STAssertNotNil(self.testFilePath, @"Test file path is nil");
}

// These tests don't retain the request or attempt to cancel it
- (void)test01Connect {
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [self.connection connectWithSuccessBlock:^{
        dispatch_semaphore_signal(semaphore);
    } failureBlock:^(NSError *error) {
        localError = error;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);
    STAssertTrue([self.connection isConnected], @"Connection unsuccessful");
}

- (void)test02List {
    [self test01Connect];
    STAssertTrue([self.connection isConnected], @"Not connected");
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    static NSString *directoryPath = @"/Users/testuser/sftp-test";
    DLSFTPRequest *request = [[DLSFTPListFilesRequest alloc] initWithDirectoryPath:directoryPath
                                                                      successBlock:^(NSArray *array) {
                                                                          dispatch_semaphore_signal(semaphore);
                                                                      }
                                                                      failureBlock:^(NSError *error) {
                                                                          localError = error;
                                                                          dispatch_semaphore_signal(semaphore);
                                                                      }];
    [self.connection addRequest:request];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);
}



- (void)tearDown
{
    [self.connection disconnect];
    STAssertFalse([self.connection isConnected], @"Disconnection unsuccessful");
    // Tear-down code here.
    [super tearDown];
}


@end
