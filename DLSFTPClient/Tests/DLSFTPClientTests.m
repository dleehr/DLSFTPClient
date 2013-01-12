//
//  DLSFTPClientTests.m
//  DLSFTPClientTests
//
//  Created by Dan Leehr on 1/6/13.
//  Copyright (c) 2013 Dan Leehr. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//  Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
// IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "DLSFTPClientTests.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "NSDictionary+SFTPFileAttributes.h"

@interface DLSFTPClientTests ()

@property (strong, nonatomic) NSDictionary *connectionInfo;
@property (strong, nonatomic) DLSFTPConnection *connection;
@property (strong, nonatomic) NSString *testFilePath;

@end


@implementation DLSFTPClientTests

- (void)setUp {
    [super setUp];
    NSString *connectionInfoPath = [[NSBundle bundleWithIdentifier:@"com.hammockdistrict.DLSFTPClientTests"] pathForResource:@"ConnectionInfo"
                                                                                                                      ofType:@"plist"];
    STAssertNotNil(connectionInfoPath, @"Please add ConnectionInfo.plist to DLSFTPClient/DLSFTPClient/Tests (Copy the ConnectionInfo-template.plist and add your own SFTP host info");
    self.connectionInfo = [NSDictionary dictionaryWithContentsOfFile:connectionInfoPath];
    DLSFTPConnection *connection = [[DLSFTPConnection alloc] initWithHostname:self.connectionInfo[@"hostname"]
                                                                         port:[self.connectionInfo[@"port"] integerValue]
                                                                     username:self.connectionInfo[@"username"]
                                                                     password:self.connectionInfo[@"password"]];
    self.connection = connection;
    STAssertNotNil(self.connection, @"Connection is nil");

    NSString *testFilePath = [[NSBundle bundleWithIdentifier:@"com.hammockdistrict.DLSFTPClientTests"] pathForResource:@"testfile"
                                                                                                                ofType:@"jpg"];
    self.testFilePath = testFilePath;
    STAssertNotNil(self.testFilePath, @"Test file path is nil");
}

- (void)tearDown
{
    [self.connection disconnect];
    STAssertFalse([self.connection isConnected], @"Disconnection unsuccessful");
    // Tear-down code here.
    [super tearDown];
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
    [self.connection listFilesInDirectory:directoryPath
                             successBlock:^(NSArray *array) {
                                 dispatch_semaphore_signal(semaphore);
                             }
                             failureBlock:^(NSError *error) {
                                 localError = error;
                                 dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);
}


- (void)test03MkDir {
    [self test01Connect];
    STAssertTrue([self.connection isConnected], @"Not connected");
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSString *basePath = self.connectionInfo[@"basePath"];
    NSString *directoryName = self.connectionInfo[@"directoryName"];
    NSString *fullPath = [basePath stringByAppendingPathComponent:directoryName];
    [self.connection makeDirectory:fullPath
                      successBlock:^(DLSFTPFile *fileOrDirectory) {
                          STAssertEqualObjects(fileOrDirectory.filename, directoryName, @"File name does not match");
                          dispatch_semaphore_signal(semaphore);
                      } failureBlock:^(NSError *error) {
                          localError = error;
                          dispatch_semaphore_signal(semaphore);
                      }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);

    // make sure the directory appears in the list
    semaphore = dispatch_semaphore_create(0);
    [self.connection listFilesInDirectory:basePath
                             successBlock:^(NSArray *array) {
                                 __block BOOL foundDirectory = NO;
                                 [array enumerateObjectsUsingBlock:^(DLSFTPFile *file, NSUInteger idx, BOOL *stop) {
                                     if ([file.filename isEqualToString:directoryName]) {
                                         *stop = foundDirectory = YES;
                                     }
                                 }];
                                 STAssertTrue(foundDirectory, @"Created directory was not found in listing");
                                 dispatch_semaphore_signal(semaphore);
                             } failureBlock:^(NSError *error) {
                                 localError = error;
                                 dispatch_semaphore_signal(semaphore);
                             }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);
}

- (void)test04RmDir {
    [self test01Connect];
    STAssertTrue([self.connection isConnected], @"Not connected");
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSString *basePath = self.connectionInfo[@"basePath"];
    NSString *directoryName = self.connectionInfo[@"directoryName"];
    NSString *fullPath = [basePath stringByAppendingPathComponent:directoryName];
    [self.connection removeDirectoryAtPath:fullPath
                         successBlock:^{
                             dispatch_semaphore_signal(semaphore);
                         } failureBlock:^(NSError *error) {
                             localError = error;
                             dispatch_semaphore_signal(semaphore);
                         }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);

    // make sure the directory is removed
    semaphore = dispatch_semaphore_create(0);
    [self.connection listFilesInDirectory:basePath
                             successBlock:^(NSArray *array) {
                                 __block BOOL foundDirectory = NO;
                                 [array enumerateObjectsUsingBlock:^(DLSFTPFile *file, NSUInteger idx, BOOL *stop) {
                                     if ([file.filename isEqualToString:directoryName]) {
                                         *stop = foundDirectory = YES;
                                     }
                                 }];
                                 STAssertFalse(foundDirectory, @"Removed directory was found in listing");
                                 dispatch_semaphore_signal(semaphore);
                             } failureBlock:^(NSError *error) {
                                 localError = error;
                                 dispatch_semaphore_signal(semaphore);
                             }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);
}

- (void)test05Upload {
    [self test01Connect];
    STAssertTrue([self.connection isConnected], @"Not connected");
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSString *basePath = self.connectionInfo[@"basePath"];
    NSString *fileName = [self.testFilePath lastPathComponent];
    NSString *destPath = [basePath stringByAppendingPathComponent:fileName];
    NSDictionary *localFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.testFilePath
                                                                                         error:&localError];
    STAssertNil(localError, localError.localizedDescription);

    [self.connection uploadFileToRemotePath:destPath
                              fromLocalPath:self.testFilePath
                              progressBlock:^BOOL(unsigned long long bytesReceived, unsigned long long bytesTotal) {
                                  return YES;
                              } successBlock:^(DLSFTPFile *file, NSDate *startTime, NSDate *finishTime) {
                                  dispatch_semaphore_signal(semaphore);
                              } failureBlock:^(NSError *error) {
                                  localError = error;
                                  dispatch_semaphore_signal(semaphore);
                              }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);

    // make sure the file listing reflects the same size
    semaphore = dispatch_semaphore_create(0);
    [self.connection listFilesInDirectory:basePath
                             successBlock:^(NSArray *array) {
                                 __block BOOL foundFile = NO;
                                 [array enumerateObjectsUsingBlock:^(DLSFTPFile *file, NSUInteger idx, BOOL *stop) {
                                     if ([file.filename isEqualToString:fileName]) {
                                         *stop = foundFile = YES;
                                         STAssertEquals(  file.attributes.fileSize
                                                        , localFileAttributes.fileSize
                                                        , @"Uploaded file size does not match local file size");
                                     }
                                 }];
                                 STAssertTrue(foundFile, @"Uploaded file not found in listing");
                                 dispatch_semaphore_signal(semaphore);
                             } failureBlock:^(NSError *error) {
                                 localError = error;
                                 dispatch_semaphore_signal(semaphore);
                             }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);
}

- (void)test06Download {
    [self test01Connect];
    STAssertTrue([self.connection isConnected], @"Not connected");
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSString *basePath = self.connectionInfo[@"basePath"];
    NSString *fileName = [self.testFilePath lastPathComponent];
    NSString *remotePath = [basePath stringByAppendingPathComponent:fileName];
    NSString *localFileName = [NSString stringWithFormat:@"testfile-%f.jpg", [[NSDate date] timeIntervalSince1970]];

    NSString *localPath = [NSTemporaryDirectory() stringByAppendingPathComponent:localFileName];

    if ([localPath length] == 0) {
        STFail(@"Unable to assemble local path for downloading");
    }

    [self.connection downloadFileAtRemotePath:remotePath
                                  toLocalPath:localPath
                                progressBlock:^BOOL(unsigned long long bytesReceived, unsigned long long bytesTotal) {
                                    return YES;
                                } successBlock:^(DLSFTPFile *file, NSDate *startTime, NSDate *finishTime) {
                                    dispatch_semaphore_signal(semaphore);
                                } failureBlock:^(NSError *error) {
                                    localError = error;
                                    dispatch_semaphore_signal(semaphore);
                                }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);

    // make sure the downloaded file matches the file we uploaded earlier

    BOOL filesEqual = [[NSFileManager defaultManager] contentsEqualAtPath:self.testFilePath
                                                                  andPath:localPath];
    STAssertTrue(filesEqual, @"Contents of downloaded file do not match uploaded");
}

- (void)test07Rename {
    [self test01Connect];
    STAssertTrue([self.connection isConnected], @"Not connected");
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSString *basePath = self.connectionInfo[@"basePath"];
    NSString *fileName = [self.testFilePath lastPathComponent];
    NSString *newName = self.connectionInfo[@"newName"];
    STAssertFalse([newName isEqualToString:fileName], @"Renaming file name cannot be equal to original name");

    NSString *remoteOriginalPath = [basePath stringByAppendingPathComponent:fileName];
    NSString *remoteRenamedPath = [basePath stringByAppendingPathComponent:newName];
    [self.connection renameOrMoveItemAtRemotePath:remoteOriginalPath
                                      withNewPath:remoteRenamedPath
                                     successBlock:^(DLSFTPFile *fileOrDirectory) {
                                         dispatch_semaphore_signal(semaphore);
                                     } failureBlock:^(NSError *error) {
                                         localError = error;
                                         dispatch_semaphore_signal(semaphore);
                                     }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);

    // Verify the renamed name appears in the directory listing
    semaphore = dispatch_semaphore_create(0);
    [self.connection listFilesInDirectory:basePath
                             successBlock:^(NSArray *array) {
                                 __block BOOL foundRenamedFile = NO;
                                 __block BOOL foundOriginalFile = NO;
                                 [array enumerateObjectsUsingBlock:^(DLSFTPFile *file, NSUInteger idx, BOOL *stop) {
                                     if ([file.filename isEqualToString:newName]) {
                                         foundRenamedFile = YES;
                                     } else if([file.filename isEqualToString:fileName]) {
                                         foundOriginalFile = YES;
                                     }
                                 }];
                                 STAssertTrue(foundRenamedFile, @"Renamed file was not found in listing");
                                 STAssertFalse(foundOriginalFile, @"Original file was found in listing but should have been renamed");
                                 dispatch_semaphore_signal(semaphore);
                             } failureBlock:^(NSError *error) {
                                 localError = error;
                                 dispatch_semaphore_signal(semaphore);
                             }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);
}

- (void)test08Delete {
    [self test01Connect];
    STAssertTrue([self.connection isConnected], @"Not connected");
    __block NSError *localError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSString *basePath = self.connectionInfo[@"basePath"];
    // delete the recently renamed file
    NSString *deleteFileName = self.connectionInfo[@"newName"];
    NSString *remoteDeletePath = [basePath stringByAppendingPathComponent:deleteFileName];
    [self.connection removeFileAtPath:remoteDeletePath
                         successBlock:^{
                             dispatch_semaphore_signal(semaphore);
                         } failureBlock:^(NSError *error) {
                             localError = error;
                             dispatch_semaphore_signal(semaphore);
                         }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);

    // check the listing to make sure the file is gone
    semaphore = dispatch_semaphore_create(0);
    [self.connection listFilesInDirectory:basePath
                             successBlock:^(NSArray *array) {
                                 __block BOOL foundDeletedFile = NO;
                                 [array enumerateObjectsUsingBlock:^(DLSFTPFile *file, NSUInteger idx, BOOL *stop) {
                                     if ([file.filename isEqualToString:deleteFileName]) {
                                         *stop = foundDeletedFile = YES;
                                     }
                                 }];
                                 STAssertFalse(foundDeletedFile, @"Deleted file was found in listing but should not have been");
                                 dispatch_semaphore_signal(semaphore);
                             } failureBlock:^(NSError *error) {
                                 localError = error;
                                 dispatch_semaphore_signal(semaphore);
                             }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    STAssertNil(localError, localError.localizedDescription);

}

/*

- (void)testCancelUpload {

}

 - (void)testCancelDownload {

 }

*/
// what else to test.  Concurrency - download and list


@end
