# DLSFTPClient

SFTP Client library and sample app for iOS, using libssh2

## Overview

DLSFTPClient is a an Objective-C wrapper around libssh2, providing simple access to upload and download files, as well as perform directory operations.  It requires iOS 5.1.  

## Status

As of 2013-06-01, DLSFTPClient is considered stable.  There are no plans to further change the API, though there may be continued efforts to further leverage [Grand Central Dispatch](https://developer.apple.com/library/ios/#documentation/Performance/Reference/GCD_libdispatch_Ref/Reference/reference.html).


## Sample Usage

You'll need to initialize a `DLSFTPConnection` object with the host and credentials.  Simple username/password as well as private key authentication are supported.

    DLSFTPConnection *connection = [[DLSFTPConnection alloc] initWithHostname:@"foo.bar.com"
                                                                         port:22
                                                                     username:@"username"
                                                                     password:@"password"];
                                                                     
To establish a connection, use `connectWithSuccessBlock:failureBlock:`

    DLSFTPClientSuccessBlock successBlock = ^{ ... };
    DLSFTPClientFailureBlock failureBlock = ^(NSError *error) { ... };
    [connection connectWithSuccessBlock:successBlock
                           failureBlock:failureBlock];

To disconnect, use `disconnect`

    [connection disconnect];

Your success and failure blocks are dispatched to the global concurrent queue.  Be sure to dispatch back to the main queue if you need to drive UI updates.                                                                     

Operations such as listing directory contents, downloading files, and moving/renaming are carried out through subclasses of `DLSFTPRequest`:

    DLSFTPClientArraySuccessBlock successBlock = ^(NSArray *files) {
        for (DLSFTPFile *sftpFile in files) {
            NSLog(@"File: %@", sftpFile.filename);
        }
    };

    DLSFTPClientFailureBlock failureBlock = ^(NSError *error) {
        NSLog(@"Error listing files: %@", error);
    };
    
    DLSFTPRequest *request = [[DLSFTPListFilesRequest alloc] initWithDirectoryPath:@"/Users/dan/"
                                                                      successBlock:successBlock
                                                                      failureBlock:failureBlock];
    [connection submitRequest:request];

The `DLSFTPFile` class is used to encapsulate file paths and metadata.

When uploading and downloading files, a progress block may be provided.  The progress block will be dispatched by the connection as it is transferring the file, and can be used to monitor progress.

## Features

1. Upload and download files via [SFTP](http://en.wikipedia.org/wiki/SSH_File_Transfer_Protocol)
2. List files
3. Create directories
4. Rename/Move files/directories
5. Remove files/directories
6. Operations can be cancelled

## Testing

DLSFTPClient includes two test case classes.  To use them, you'll need to copy `ConnectionInfo-template.plist` to `ConnectionInfo.plist` and update the values with credentials and file paths for your own server.  To test private key authentication, you'll need to add a `privatekey.pem` file as well.

## Remaining issues

The Demo App is incomplete and needs some polish.

## Project Dependencies

1. [libssh2](https://github.com/x2on/libssh2-for-iOS) - Provides a shell script to build libssh2.a Static Library and headers

## License

DLSFTPClient is open-source under the BSD license. See the LICENSE file for more info.

