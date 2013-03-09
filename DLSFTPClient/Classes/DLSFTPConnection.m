//
//  DLSFTPConnection.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/11/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
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

#include <fcntl.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include "libssh2.h"
#include "libssh2_config.h"
#include "libssh2_sftp.h"
#import "DLSFTPRequest.h"

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
#define NEEDS_DISPATCH_RETAIN_RELEASE 0
#else                                         // iOS 5.X or earlier
#define NEEDS_DISPATCH_RETAIN_RELEASE 1
#endif

// keyboard-interactive response
static void response(const char *name,   int name_len, const char *instruction,   int instruction_len,   int num_prompts,   const LIBSSH2_USERAUTH_KBDINT_PROMPT *prompts,   LIBSSH2_USERAUTH_KBDINT_RESPONSE *responses,   void **abstract);


NSString * const SFTPClientErrorDomain = @"SFTPClientErrorDomain";
NSString * const SFTPClientUnderlyingErrorKey = @"SFTPClientUnderlyingError";

static const NSUInteger cDefaultSSHPort = 22;
static const NSTimeInterval cDefaultConnectionTimeout = 15.0;
static const NSTimeInterval cIdleTimeout = 60.0;
static const size_t cBufferSize = 8192;

#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "NSDictionary+SFTPFileAttributes.h"

// goes away

#define CHECK_REQUEST_CANCELLED if (request.isCancelled) { \
    [weakSelf failWithErrorCode:eSFTPClientErrorCancelledByUser \
               errorDescription:@"Cancelled by user" \
                underlyingError:nil \
                   failureBlock:failureBlock]; \
    [weakSelf removeRequest:request]; \
    return; \
}

// goes away

#define CHECK_PATH(path) if ([path length] == 0) { \
    [weakSelf failWithErrorCode:eSFTPClientErrorInvalidArguments \
               errorDescription:@"Invalid path" \
                underlyingError:nil \
                   failureBlock:failureBlock]; \
    [weakSelf removeRequest:request]; \
    return; \
}


@interface DLSFTPConnection () {

    // socket queue
    dispatch_queue_t _socketQueue;

    // file IO
    dispatch_queue_t _fileIOQueue; // not necessary

    // request queue
    dispatch_queue_t _requestQueue;

    // connection group
    dispatch_group_t _connectionGroup;

    // idle timer
    dispatch_source_t _idleTimer;
}

// These blocks are only used for connection operation, name them so
@property (nonatomic, copy) DLSFTPClientSuccessBlock connectionSuccessBlock;
@property (nonatomic, copy) DLSFTPClientFailureBlock connectionFailureBlock;

@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *keypath;
@property (nonatomic, copy) NSString *hostname;
@property (nonatomic, assign) NSUInteger port;

@property (nonatomic, assign) int socket;
@property (nonatomic, assign) LIBSSH2_SESSION *session;
@property (nonatomic, assign) LIBSSH2_SFTP *sftp;

// Request handling
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic, strong) DLSFTPRequest *currentRequest;
- (void)addRequest:(DLSFTPRequest *)request;
- (void)removeRequest:(DLSFTPRequest *)request;

@end


@implementation DLSFTPConnection

@synthesize session=_session;
@synthesize sftp=_sftp;

#pragma mark Lifecycle

- (id)init {
    return [self initWithHostname:nil
                             port:0
                         username:nil
                         password:nil];
}

- (id)initWithHostname:(NSString *)hostname
              username:(NSString *)username
              password:(NSString *)password {
    return [self initWithHostname:hostname
                             port:cDefaultSSHPort
                         username:username
                         password:password
                          keypath:nil];
}

- (id)initWithHostname:(NSString *)hostname
                  port:(NSUInteger)port
              username:(NSString *)username
              password:(NSString *)password {
    return [self initWithHostname:hostname
                             port:port
                         username:username
                         password:password
                          keypath:nil];
}

- (id)initWithHostname:(NSString *)hostname
              username:(NSString *)username
               keypath:(NSString *)keypath
            passphrase:(NSString *)passphrase {

    return [self initWithHostname:hostname
                             port:cDefaultSSHPort
                         username:username
                         password:passphrase
                          keypath:keypath];
}

- (id)initWithHostname:(NSString *)hostname
                  port:(NSUInteger)port
              username:(NSString *)username
               keypath:(NSString *)keypath
            passphrase:(NSString *)passphrase {
    return [self initWithHostname:hostname
                             port:port
                         username:username
                         password:passphrase
                          keypath:keypath];
}


- (id)initWithHostname:(NSString *)hostname
                  port:(NSUInteger)port
              username:(NSString *)username
              password:(NSString *)password
               keypath:(NSString *)keypath {
    self = [super init];
    if (self) {
        self.hostname = hostname;
        self.port = port;
        self.username = username;
        self.password = password;
        self.keypath = keypath;
        self.socket = -1;
        self.requests = [[NSMutableArray alloc] init];
        _socketQueue = dispatch_queue_create("com.hammockdistrict.SFTPClient.socket", DISPATCH_QUEUE_SERIAL);
        _fileIOQueue = dispatch_queue_create("com.hammockdistrict.SFTPClient.fileio", DISPATCH_QUEUE_SERIAL);
        _requestQueue = dispatch_queue_create("com.hammockdistrict.SFTPClient.request", DISPATCH_QUEUE_CONCURRENT);
        _connectionGroup = dispatch_group_create();
        _idleTimer = NULL; // lazily loaded
    }
    return self;
}

- (void)dealloc {
    #if NEEDS_DISPATCH_RETAIN_RELEASE
    dispatch_release(_requestQueue);
    _requestQueue = NULL;
    dispatch_release(_socketQueue);
    _socketQueue = NULL;
    dispatch_release(_fileIOQueue);
    _fileIOQueue = NULL;
    dispatch_release(_connectionGroup);
    _connectionGroup = NULL;
    dispatch_release(_idleTimer);
    _idleTimer = NULL;
    #endif
    [self disconnectSocket];
}

- (dispatch_queue_t)socketQueue {
    return _socketQueue;
}
- (dispatch_queue_t)fileIOQueue {
    return _fileIOQueue;
}
- (dispatch_queue_t)requestQueue {
    return _requestQueue;
}

- (dispatch_source_t)idleTimer {
    if (_idleTimer == NULL) {
        _idleTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _socketQueue);
        dispatch_source_set_timer(_idleTimer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
        __weak DLSFTPConnection *weakSelf = self;
        dispatch_source_set_event_handler(_idleTimer, ^{
            [weakSelf disconnect];
            [weakSelf cancelIdleTimer];
        });
        dispatch_resume(_idleTimer);
    }
    return _idleTimer;
}

- (void)setSession:(LIBSSH2_SESSION *)session {
    // destroy if exists
    if (_session) {
        // check if _sftp exists
        self.sftp = NULL;
        while (libssh2_session_disconnect(_session, "") == LIBSSH2_ERROR_EAGAIN) {
            waitsocket(self.socket, _session);
        }
        while (libssh2_session_free(_session) == LIBSSH2_ERROR_EAGAIN) {
            waitsocket(self.socket, _session);
        }
        _session = NULL;
    }
    _session = session;
}

- (LIBSSH2_SESSION *)session {
    if (_session == NULL) {
        _session = libssh2_session_init_ex(NULL, NULL, NULL, (__bridge void *)self);
        // set non-blocking
        if (_session) {
            libssh2_session_set_blocking(_session, 0);
        }
    }
    return _session;
}

- (void)setSftp:(LIBSSH2_SFTP *)sftp {
    if (_sftp) {
        while (libssh2_sftp_shutdown(_sftp) == LIBSSH2SFTP_EAGAIN) {
            waitsocket(self.socket, _session);
        }
    }
    _sftp = sftp;
}

// If there's an error initializing sftp, such as a non-authenticated connection, this will return NULL and we must check the session error
- (LIBSSH2_SFTP *)sftp {
    if (_sftp == NULL) {
        LIBSSH2_SESSION *session = self.session;
        // initialize sftp in non-blocking
        while (   (_sftp = libssh2_sftp_init(session)) == NULL
               && (libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN)) {
            waitsocket(self.socket, session);
        }
    }
    return _sftp;
}

#pragma mark - Private

- (void)clearConnectionBlocks {
    self.connectionFailureBlock = nil;
    self.connectionSuccessBlock = nil;
}

- (void)disconnectSocket {
    if (_idleTimer) { // avoid cancelling after dealloc
        [self cancelIdleTimer];
    }
    self.sftp = NULL;
    self.session = NULL;
    if (self.socket >= 0) {
        if(close(self.socket) == -1) {
            NSLog(@"Error closing socket: %d", errno);
        }
        self.socket = -1;
    }
}

- (void)startSFTPSession {
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_group_async(_connectionGroup,_socketQueue, ^{
        int socketFD = self.socket;
        LIBSSH2_SESSION *session = self.session;

        if (session == NULL) { // unable to access the session
            // close the socket
            [weakSelf disconnectSocket];
            // unable to initialize session
            [weakSelf failConnectionWithErrorCode:eSFTPClientErrorUnableToInitializeSession
                   errorDescription:@"Unable to initialize libssh2 session"];
            weakSelf.connectionSuccessBlock = nil;
            return;
        }
        // valid session, get the socket descriptor
        // must be called from socket's queue
        int result;
        NSLog(@"Handshaking session");
        while (   (result = libssh2_session_handshake(session, socketFD) == LIBSSH2_ERROR_EAGAIN)
               && weakSelf.isConnected) {
            waitsocket(socketFD, session);
        }
        if (result) {
            // handshake failed
            // free the session and close the socket
            [weakSelf disconnectSocket];

            NSString *errorDescription = [NSString stringWithFormat:@"Handshake failed with code %d", result];
            NSError *error = [NSError errorWithDomain:SFTPClientErrorDomain
                                                 code:eSFTPClientErrorHandshakeFailed
                                             userInfo:@{ NSLocalizedDescriptionKey : errorDescription, SFTPClientUnderlyingErrorKey : @(result) }];
            if (weakSelf.connectionFailureBlock) {
                DLSFTPClientFailureBlock failureBlock = weakSelf.connectionFailureBlock;
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    failureBlock(error);
                });
            }
            [weakSelf clearConnectionBlocks];
            return;
        }

        // handshake OK.

        // waitsocket just waits for the socket.  shouldn't use much CPU or anything and lets us be efficient about retrying a potentially blocking operation

        // get user auth methods
        char * authmethods = NULL;
        while (   (authmethods = libssh2_userauth_list(session, [self.username UTF8String], strlen([self.username UTF8String]))) == NULL
               && (libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN)
               && weakSelf.isConnected) {
            waitsocket(socketFD, session);
        }

        if (authmethods && strstr(authmethods, "publickey") && self.keypath) {
            while (   (result = libssh2_userauth_publickey_fromfile(session, [self.username UTF8String], NULL, [self.keypath UTF8String], [self.password UTF8String]) == LIBSSH2_ERROR_EAGAIN)
                   && weakSelf.isConnected) {
                waitsocket(socketFD, session);
            }
        } else if (authmethods && strstr(authmethods, "password")) {
            while (   (result = libssh2_userauth_password(session, [self.username UTF8String], [self.password UTF8String]) == LIBSSH2_ERROR_EAGAIN)
                   && weakSelf.isConnected) {
                waitsocket(socketFD, session);
            }
        } else if(authmethods && strstr(authmethods, "keyboard-interactive")) {
            while (   (result = libssh2_userauth_keyboard_interactive(session, [_username UTF8String], response) == LIBSSH2_ERROR_EAGAIN)
                   && weakSelf.isConnected) {
                waitsocket(socketFD, session);
            }
        } else {
            result = LIBSSH2_ERROR_METHOD_NONE;
        }

        if (libssh2_userauth_authenticated(session) == 0) {
            // authentication failed
            // disconnect to disconnect/free the session and close the socket
            [weakSelf disconnectSocket];
            NSString *errorDescription = [NSString stringWithFormat:@"Authentication failed with code %d", result];
            NSError *error = [NSError errorWithDomain:SFTPClientErrorDomain
                                                 code:eSFTPClientErrorAuthenticationFailed
                                             userInfo:@{ NSLocalizedDescriptionKey : errorDescription, SFTPClientUnderlyingErrorKey : @(result) }];
            if (weakSelf.connectionFailureBlock) {
                DLSFTPClientFailureBlock failureBlock = weakSelf.connectionFailureBlock;
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    failureBlock(error);
                });
            }
            [weakSelf clearConnectionBlocks];
            return;
        }
        // authentication succeeded
        // session is now created and we can use it
        if (weakSelf.connectionSuccessBlock) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), weakSelf.connectionSuccessBlock);
        }
        [weakSelf clearConnectionBlocks];
        return;
    });
}

- (void)addRequest:(DLSFTPRequest *)request {
    NSLog(@"Adding request: %@", request);
    request.connection = self;
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_barrier_async(_requestQueue, ^{
        [weakSelf.requests addObject:request];
        [weakSelf cancelIdleTimer];
        [weakSelf startNextRequest];
    });
}

- (void)removeRequest:(DLSFTPRequest *)request {
    NSLog(@"Removing request: %@", request);
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_barrier_async(_requestQueue, ^{
        request.connection = nil;
        if ([weakSelf.currentRequest isEqual:request]) {
            [weakSelf.currentRequest cancel];
            weakSelf.currentRequest = nil;
            return;
        }
        [weakSelf.requests removeObject:request];
        if ([weakSelf.requests count] == 0) {
            // start the idle timer
            [weakSelf startIdleTimer];
        }
    });
}

- (void)startNextRequest {
    if (self.currentRequest) {
        return;
    }
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_barrier_async(_requestQueue, ^{
        if (weakSelf.currentRequest) {
            return;
        }
        if([weakSelf.requests count] > 0) {
            DLSFTPRequest *request = [weakSelf.requests objectAtIndex:0];
            [weakSelf.requests removeObjectAtIndex:0];
            weakSelf.currentRequest = request;
            [weakSelf startRequest];
        }
    });
}

- (void)startRequest {
    NSLog(@"Starting request: %@", self.currentRequest);
    DLSFTPRequest *request = self.currentRequest;
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_group_notify(_connectionGroup, _socketQueue, ^{
        [request start];
        if (request.error) {
            [request fail];
        } else {
            [request finish];
        }
        weakSelf.currentRequest = nil;
        [weakSelf startNextRequest];
    });
}

- (void)startIdleTimer {
    // restart the timer, by setting its fire time and repeat interval
    dispatch_time_t fireTime = dispatch_time(DISPATCH_TIME_NOW, cIdleTimeout * NSEC_PER_SEC);
    dispatch_source_set_timer([self idleTimer], fireTime, DISPATCH_TIME_FOREVER, 0);
}

- (void)cancelIdleTimer {
    // set the fire time to forever
    dispatch_source_set_timer([self idleTimer], DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
}

#pragma mark Public

- (void)cancelAllRequests {
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_barrier_async(_requestQueue, ^{
        for (DLSFTPRequest *request in weakSelf.requests) {
            [request cancel];
        }
        [weakSelf.requests removeAllObjects];
        [weakSelf startIdleTimer];
    });
}

- (NSUInteger)requestCount {
    __block NSUInteger count = 0;
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_sync(_requestQueue, ^{
        count = [weakSelf.requests count];
    });
    NSLog(@"Returning count: %d", count);
    return count;
}

// just if the socket is connected
- (BOOL)isConnected {
    return self.socket >= 0;
}

- (void)failConnectionWithErrorCode:(eSFTPClientErrorCode)errorCode
         errorDescription:(NSString *)errorDescription {
    NSError *error = [NSError errorWithDomain:SFTPClientErrorDomain
                                         code:errorCode
                                     userInfo:@{ NSLocalizedDescriptionKey : errorDescription }];
    if (self.connectionFailureBlock) {
        DLSFTPClientFailureBlock failureBlock = self.connectionFailureBlock;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureBlock(error);
        });
        [self clearConnectionBlocks];
    }
}

- (void)connectWithSuccessBlock:(DLSFTPClientSuccessBlock)successBlock
                   failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    if (self.connectionSuccessBlock || self.connectionFailureBlock) {
        // last connection not yet connected
        NSError *error = [NSError errorWithDomain:SFTPClientErrorDomain
                                             code:eSFTPClientErrorOperationInProgress
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Connection in progress" }];
        if (failureBlock) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                failureBlock(error);
            });
        }
        return;
    }
    self.connectionSuccessBlock = successBlock;
    self.connectionFailureBlock = failureBlock;
    if (   ([self.hostname length] == 0)
        || ([self.username length] == 0)
        || ([self.password length] == 0 && [self.keypath length] == 0)
        || (self.port == 0)) {
                // don't have valid arguments
        [self failConnectionWithErrorCode:eSFTPClientErrorInvalidArguments
                         errorDescription:@"Invalid arguments"];
        return;
    } else if(self.socket >= 0) {
        // already have a socket
        // last connection not yet connected
        [self failConnectionWithErrorCode:eSFTPClientErrorAlreadyConnected
                         errorDescription:@"Already connected"];
        return;
    } else {
        __weak DLSFTPConnection *weakSelf = self;
        // set up a timeout handler
        __block dispatch_source_t timeoutTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
        dispatch_time_t fireTime = dispatch_time(DISPATCH_TIME_NOW, cDefaultConnectionTimeout * NSEC_PER_SEC);
        dispatch_source_set_timer(timeoutTimer, fireTime, DISPATCH_TIME_FOREVER, 0);
        dispatch_source_set_event_handler(timeoutTimer, ^{
            NSLog(@"timeout Timer fired, disconnecting socket");
            // timeout fired, close the socket
            dispatch_sync([weakSelf socketQueue], ^{
                [weakSelf disconnectSocket]; // closes on socketQueue
            });
            // and fail
            [weakSelf failConnectionWithErrorCode:eSFTPClientErrorConnectionTimedOut
                                 errorDescription:@"Connection timed out"];
            // clear out the queued success block
            weakSelf.connectionSuccessBlock = nil;
            dispatch_source_cancel(timeoutTimer);
        });

        // On cancel, release the timer if necessary
        dispatch_source_set_cancel_handler(timeoutTimer, ^{
            #if NEEDS_DISPATCH_RETAIN_RELEASE
            dispatch_release(timeoutTimer);
            #endif
            timeoutTimer = NULL;
        });

        // start the timer
        if (timeoutTimer) {
            dispatch_resume(timeoutTimer);
        }

        // initialize and connect the socket on the socket queue
        dispatch_group_async(_connectionGroup, _socketQueue, ^{
            unsigned long hostaddr = inet_addr([weakSelf.hostname UTF8String]);
            weakSelf.socket = socket(AF_INET, SOCK_STREAM, 0);
            if (weakSelf.socket == -1) {
                [weakSelf failConnectionWithErrorCode:eSFTPClientErrorSocketError
                                     errorDescription:@"Unable to create socket"];
                weakSelf.connectionSuccessBlock = nil;
                return;
            }
            struct sockaddr_in soin;
            soin.sin_family = AF_INET;
            soin.sin_port = htons(weakSelf.port);
            soin.sin_addr.s_addr = hostaddr;

            int result = connect(weakSelf.socket, (struct sockaddr*)(&soin),sizeof(struct sockaddr_in));
            // cancel the timeout timer after connecting
            if (timeoutTimer) {
                dispatch_source_cancel(timeoutTimer);
            }
            if (result == 0) {
                // connected socket, start the SFTP session
                [weakSelf startSFTPSession];
            } else {
                NSString *errorDescription = [NSString stringWithFormat:@"Unable to connect: socket error: %d", result];
                [weakSelf failConnectionWithErrorCode:eSFTPClientErrorUnableToConnect
                                     errorDescription:errorDescription];
                weakSelf.connectionSuccessBlock = nil;
                return;
            }
        });
    }
}

- (void)disconnect {
    [self cancelAllRequests];
    dispatch_sync(_socketQueue, ^{
        [self disconnectSocket];
    });
    if (self.connectionFailureBlock) { // not yet connected
        [self failConnectionWithErrorCode:eSFTPClientErrorCancelledByUser
                         errorDescription:@"Cancelled by user"];
    }
}

#pragma mark SFTP

// This goes away
- (void)failWithErrorCode:(eSFTPClientErrorCode)errorCode
         errorDescription:(NSString *)errorDescription
          underlyingError:(NSNumber *)underlyingError
             failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    NSError *error = nil;
    if (underlyingError == nil) {
        error = [NSError errorWithDomain:SFTPClientErrorDomain
                                    code:errorCode
                                userInfo:@{ NSLocalizedDescriptionKey : errorDescription }
                 ];
    } else {
        error = [NSError errorWithDomain:SFTPClientErrorDomain
                                    code:errorCode
                                userInfo:@{ NSLocalizedDescriptionKey : errorDescription, SFTPClientUnderlyingErrorKey : underlyingError }
                 ];
    }

    if (failureBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureBlock(error);
        });
    }
}

// list files
- (DLSFTPRequest *)listFilesInDirectory:(NSString *)directoryPath
                           successBlock:(DLSFTPClientArraySuccessBlock)successBlock
                           failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    return nil;
}

- (DLSFTPRequest *)makeDirectory:(NSString *)directoryPath
                    successBlock:(DLSFTPClientFileMetadataSuccessBlock)successBlock
                    failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    return nil;
}

- (DLSFTPRequest *)renameOrMoveItemAtRemotePath:(NSString *)remotePath
                                    withNewPath:(NSString *)newPath
                                   successBlock:(DLSFTPClientFileMetadataSuccessBlock)successBlock
                                   failureBlock:(DLSFTPClientFailureBlock)failureBlock {

    DLSFTPRequest *request = [[DLSFTPRequest alloc] init];
    [self addRequest:request];
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_group_notify(_connectionGroup, _socketQueue, ^{
        CHECK_REQUEST_CANCELLED
        CHECK_PATH(remotePath)
        CHECK_PATH(newPath)
        if ([weakSelf isConnected] == NO) {
            [weakSelf failWithErrorCode:eSFTPClientErrorNotConnected
                       errorDescription:@"Socket not connected"
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
        }

        LIBSSH2_SESSION *session = self.session;
        LIBSSH2_SFTP *sftp = self.sftp;
        int socketFD = self.socket;

        if (sftp == NULL) {
            // unable to initialize sftp
            int lastError = libssh2_session_last_errno(session);
            char *errmsg = NULL;
            int errmsg_len = 0;
            libssh2_session_last_error(session, &errmsg, &errmsg_len, 0);
            NSString *errorDescription = [NSString stringWithFormat:@"Unable to initialize sftp: libssh2 session error %s: %d"
                                          , errmsg
                                          , lastError];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToInitializeSFTP
                       errorDescription:errorDescription
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // sftp is now valid

        int result;

        // libssh2_sftp_rename includes overwrite | atomic | native
        while(  ((result = (libssh2_sftp_rename(sftp, [remotePath UTF8String], [newPath UTF8String]))) == LIBSSH2SFTP_EAGAIN)
              && request.isCancelled == NO) {
            waitsocket(socketFD, session);
        }
        
        CHECK_REQUEST_CANCELLED

        if (result) {
            // unable to rename
            NSString *errorDescription = [NSString stringWithFormat:@"Unable to rename item: SFTP Status Code %d", result];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToRename
                       errorDescription:errorDescription
                        underlyingError:@(result)
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // item renamed, stat the new item
        // can use stat since we don't need a descriptor
        LIBSSH2_SFTP_ATTRIBUTES attributes;
        while (  ((result = libssh2_sftp_stat(sftp, [newPath UTF8String], &attributes)) == LIBSSH2SFTP_EAGAIN)
               && request.isCancelled == NO) {
            waitsocket(socketFD, session);
        }

        CHECK_REQUEST_CANCELLED

        if (result) {
            // unable to stat the new item
            NSString *errorDescription = [NSString stringWithFormat:@"Unable to stat newly renamed item: SFTP Status Code %d", result];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToStatFile
                       errorDescription:errorDescription
                        underlyingError:@(result)
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // attributes are valid
        NSDictionary *attributesDictionary = [NSDictionary dictionaryWithAttributes:attributes];
        DLSFTPFile *renamedItem = [[DLSFTPFile alloc] initWithPath:newPath
                                                        attributes:attributesDictionary];

        if (successBlock) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                successBlock(renamedItem);
            });
        }
        [weakSelf removeRequest:request];
    });
    return request;
}

- (DLSFTPRequest *)removeFileAtPath:(NSString *)remotePath
                       successBlock:(DLSFTPClientSuccessBlock)successBlock
                       failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    DLSFTPRequest *request = [[DLSFTPRequest alloc] init];
    [self addRequest:request];
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_group_notify(_connectionGroup, _socketQueue, ^{
        CHECK_REQUEST_CANCELLED
        CHECK_PATH(remotePath)
        if ([weakSelf isConnected] == NO) {
            [weakSelf failWithErrorCode:eSFTPClientErrorNotConnected
                       errorDescription:@"Socket not connected"
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
        }

        LIBSSH2_SESSION *session = self.session;
        LIBSSH2_SFTP *sftp = self.sftp;
        int socketFD = self.socket;

        if (sftp == NULL) {
            // unable to initialize sftp
            int lastError = libssh2_session_last_errno(session);
            char *errmsg = NULL;
            int errmsg_len = 0;
            libssh2_session_last_error(session, &errmsg, &errmsg_len, 0);

            NSString *errorDescription = [NSString stringWithFormat:@"Unable to initialize sftp: libssh2 session error %s: %d"
                                          , errmsg
                                          , lastError];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToInitializeSFTP
                       errorDescription:errorDescription
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // sftp is now valid

        int result;
        while(  ((result = (libssh2_sftp_unlink(sftp, [remotePath UTF8String]))) == LIBSSH2SFTP_EAGAIN)
              && request.isCancelled == NO) {
            waitsocket(socketFD, session);
        }
        
        CHECK_REQUEST_CANCELLED

        if (result) {
            // unable to remove
            NSString *errorDescription = [NSString stringWithFormat:@"Unable to remove file: SFTP Status Code %d", result];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToRename
                       errorDescription:errorDescription
                        underlyingError:@(result)
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // file removed
        if (successBlock) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                successBlock();
            });
        }
        [weakSelf removeRequest:request];
    });
    return request;
}

- (DLSFTPRequest *)removeDirectoryAtPath:(NSString *)remotePath
                            successBlock:(DLSFTPClientSuccessBlock)successBlock
                            failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    DLSFTPRequest *request = [[DLSFTPRequest alloc] init];
    [self addRequest:request];
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_group_notify(_connectionGroup, _socketQueue, ^{
        CHECK_REQUEST_CANCELLED
        CHECK_PATH(remotePath)
        if ([weakSelf isConnected] == NO) {
            [weakSelf failWithErrorCode:eSFTPClientErrorNotConnected
                       errorDescription:@"Socket not connected"
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
        }

        LIBSSH2_SESSION *session = self.session;
        LIBSSH2_SFTP *sftp = self.sftp;
        int socketFD = self.socket;

        if (sftp == NULL) {
            // unable to initialize sftp
            int lastError = libssh2_session_last_errno(session);
            char *errmsg = NULL;
            int errmsg_len = 0;
            libssh2_session_last_error(session, &errmsg, &errmsg_len, 0);

            NSString *errorDescription = [NSString stringWithFormat:@"Unable to initialize sftp: libssh2 session error %s: %d"
                                          , errmsg
                                          , lastError];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToInitializeSFTP
                       errorDescription:errorDescription
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // sftp is now valid

        int result;
        while(  ((result = (libssh2_sftp_rmdir(sftp, [remotePath UTF8String]))) == LIBSSH2SFTP_EAGAIN)
              && request.isCancelled == NO) {
            waitsocket(socketFD, session);
        }

        CHECK_REQUEST_CANCELLED
        
        if (result) {
            // unable to remove
            NSString *errorDescription = [NSString stringWithFormat:@"Unable to remove directory: SFTP Status Code %d", result];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToRename
                       errorDescription:errorDescription
                        underlyingError:@(result)
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // directory removed
        if (successBlock) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                successBlock();
            });
        }
        [weakSelf removeRequest:request];
    });
    return request;
}

// should make custom DLSFTPRequest subclasses that do things?
- (DLSFTPRequest *)downloadFileAtRemotePath:(NSString *)remotePath
                                toLocalPath:(NSString *)localPath
                                     resume:(BOOL)resume
                              progressBlock:(DLSFTPClientProgressBlock)progressBlock
                               successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
                               failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    return nil;
}


- (DLSFTPRequest *)uploadFileToRemotePath:(NSString *)remotePath
                            fromLocalPath:(NSString *)localPath
                            progressBlock:(DLSFTPClientProgressBlock)progressBlock
                             successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
                             failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    DLSFTPRequest *request = [[DLSFTPRequest alloc] init];
    [self addRequest:request];
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_group_notify(_connectionGroup, _socketQueue, ^{
        CHECK_REQUEST_CANCELLED
        CHECK_PATH(remotePath)
        CHECK_PATH(localPath)
        if ([weakSelf isConnected] == NO) {
            [weakSelf failWithErrorCode:eSFTPClientErrorNotConnected
                       errorDescription:@"Socket not connected"
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
        }
        // verify local file is readable prior to upload
        if ([[NSFileManager defaultManager] isReadableFileAtPath:localPath] == NO) {
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToOpenLocalFileForReading
                       errorDescription:@"Local file is not readable"
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        NSError __autoreleasing *attributesError = nil;
        NSDictionary *localFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:localPath
                                                                                             error:&attributesError];
        if (localFileAttributes == nil) {
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToOpenLocalFileForReading
                       errorDescription: @"Unable to get attributes of Local file"
                        underlyingError:@(attributesError.code)
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        LIBSSH2_SESSION *session = self.session;
        LIBSSH2_SFTP *sftp = self.sftp;
        int socketFD = self.socket;
        if (sftp == NULL) {
            // unable to initialize sftp
            int lastError = libssh2_session_last_errno(session);
            char *errmsg = NULL;
            int errmsg_len = 0;
            libssh2_session_last_error(session, &errmsg, &errmsg_len, 0);
            NSString *errorDescription = [NSString stringWithFormat:@"Unable to initialize sftp: libssh2 session error %s: %d"
                                          , errmsg
                                          , lastError];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToInitializeSFTP
                       errorDescription:errorDescription
                        underlyingError:nil
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // sftp is now valid
        // get a file handle for the file to upload
        // write, create, or truncate.  There's also append and excl
        // permissions 644 (can customize later)
        // TODO: customize permissions later or base them on local file?
        // TODO: resume uploads?  first stat the remote file if it exists
        LIBSSH2_SFTP_HANDLE *handle = NULL;
                     while (   (handle = libssh2_sftp_open(  sftp
                                                           , [remotePath UTF8String]
                                                           , LIBSSH2_FXF_WRITE|LIBSSH2_FXF_CREAT|LIBSSH2_FXF_READ
                                                           , LIBSSH2_SFTP_S_IRUSR|LIBSSH2_SFTP_S_IWUSR|
                                                             LIBSSH2_SFTP_S_IRGRP|LIBSSH2_SFTP_S_IROTH)) == NULL
                            && (libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN)
                            && request.isCancelled == NO) {
            waitsocket(socketFD, session);
        }

        CHECK_REQUEST_CANCELLED

        if (handle == NULL) {
            // unable to open file handle, get last error
            unsigned long lastError = libssh2_sftp_last_error(sftp);
            NSString *errorDescription = [NSString stringWithFormat:@"Unable to open file for writing: SFTP Status Code %ld", lastError];
            [weakSelf failWithErrorCode:eSFTPClientErrorUnableToOpenFile
                       errorDescription:errorDescription
                        underlyingError:@(lastError)
                           failureBlock:failureBlock];
            [weakSelf removeRequest:request];
            return;
        }

        // jump to the file IO queue
        dispatch_async(_fileIOQueue, ^{
            __block dispatch_io_t channel;
            void(^cleanup_handler)(int) = ^(int error) {
                if (error) {
                    printf("Error creating channel: %d", error);
                }
                NSLog(@"finished reading file for upload, cleaning up channel");
                #if NEEDS_DISPATCH_RETAIN_RELEASE
                dispatch_release(channel);
                #endif
            };

            channel = dispatch_io_create_with_path(  DISPATCH_IO_STREAM
                                                   , [localPath UTF8String]
                                                   , O_RDONLY
                                                   , 0
                                                   , _fileIOQueue
                                                   , cleanup_handler
                                                   );

            // dispatch source to invoke progress handler block

            dispatch_source_t progressSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
            __block unsigned long long totalBytesSent = 0ull;
            unsigned long long filesize = [localFileAttributes fileSize];
            dispatch_source_set_event_handler(progressSource, ^{
                totalBytesSent += dispatch_source_get_data(progressSource);
                if (progressBlock) {
                    progressBlock(totalBytesSent, filesize);
                }
            });

            dispatch_source_set_cancel_handler(progressSource, ^{
#if NEEDS_DISPATCH_RETAIN_RELEASE
                dispatch_release(progressSource);
#endif
            });

            dispatch_resume(progressSource);

            NSDate *startTime = [NSDate date];
            __block int sftp_result = 0;
            __block int read_error = 0;

            // progress source gets cancelled in cleanup block

            // this block gets dispatched on the socket queue
            dispatch_block_t read_finished_block = ^{
                NSDate *finishTime = [NSDate date];
                if (request.isCancelled) {
                    // Cancelled by user
                    while(libssh2_sftp_close_handle(handle) == LIBSSH2SFTP_EAGAIN) {
                        waitsocket(socketFD, session);
                    }

                    // delete remote file on cancel?
                    [weakSelf failWithErrorCode:eSFTPClientErrorCancelledByUser
                               errorDescription:@"Cancelled by user."
                                underlyingError:nil
                                   failureBlock:failureBlock];
                    [weakSelf removeRequest:request];
                    return;
                }

                if (read_error != 0) {
                    // error reading file
                    NSString *errorDescription = [NSString stringWithFormat:@"Read local file failed with code %d", read_error];
                    [weakSelf failWithErrorCode:eSFTPClientErrorUnableToReadFile
                               errorDescription:errorDescription
                                underlyingError:@(read_error)
                                   failureBlock:failureBlock];
                    [weakSelf removeRequest:request];
                    return;
                }

                if (sftp_result < 0) { // error on last call to upload
                    // get the error before closing the file
                    int result = libssh2_sftp_last_error(sftp);
                    while(   (libssh2_sftp_close_handle(handle) == LIBSSH2SFTP_EAGAIN)
                          && request.isCancelled == NO) {
                        waitsocket(socketFD, session);
                    }
                    CHECK_REQUEST_CANCELLED
                    // error writing
                    NSString *errorDescription = [NSString stringWithFormat:@"Write file failed with code %d.", result];
                    [weakSelf failWithErrorCode:eSFTPClientErrorUnableToWriteFile
                               errorDescription:errorDescription
                                underlyingError:@(result)
                                   failureBlock:failureBlock];
                    [weakSelf removeRequest:request];
                    return;
                }

                int result;
                // stat the remote file after uploading
                LIBSSH2_SFTP_ATTRIBUTES attributes;
                while (   ((result = libssh2_sftp_fstat(handle, &attributes)) == LIBSSH2SFTP_EAGAIN)
                       && request.isCancelled == NO){
                    waitsocket(socketFD, session);
                }
                CHECK_REQUEST_CANCELLED
                if (result) {
                    // unable to stat the file
                    NSString *errorDescription = [NSString stringWithFormat:@"Unable to stat file: SFTP Status Code %d", result];
                    [weakSelf failWithErrorCode:eSFTPClientErrorUnableToStatFile
                               errorDescription:errorDescription
                                underlyingError:@(result)
                                   failureBlock:failureBlock];
                    [weakSelf removeRequest:request];
                    return;
                }

                // now close the remote handle
                while(   ((result = libssh2_sftp_close_handle(handle)) == LIBSSH2SFTP_EAGAIN)
                      && request.isCancelled == NO) {
                    waitsocket(socketFD, session);
                }
                CHECK_REQUEST_CANCELLED
                if (result) {
                    NSString *errorDescription = [NSString stringWithFormat:@"Close file handle failed with code %d", result];
                    [weakSelf failWithErrorCode:eSFTPClientErrorUnableToCloseFile
                               errorDescription:errorDescription
                                underlyingError:nil
                                   failureBlock:failureBlock];
                    [weakSelf removeRequest:request];
                    return;
                }

                NSDictionary *attributesDictionary = [NSDictionary dictionaryWithAttributes:attributes];
                DLSFTPFile *file = [[DLSFTPFile alloc] initWithPath:remotePath
                                                         attributes:attributesDictionary];

                if (successBlock) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        successBlock(file, startTime, finishTime);
                    });
                }
                [weakSelf removeRequest:request];
            }; // end of read_finished_block

            // dispatch this block on file io queue
            dispatch_block_t channel_cleanup_block = ^{
                dispatch_source_cancel(progressSource);
                dispatch_io_close(channel, DISPATCH_IO_STOP);
                dispatch_async(_socketQueue, read_finished_block);
            }; // end channel cleanup block

            dispatch_io_read(  channel
                             , 0 // for stream, offset is ignored
                             , SIZE_MAX
                             , _socketQueue // blocks with data queued on the socket queue
                             , ^(bool done, dispatch_data_t data, int error) {
                                 // dispatch_data_apply would be ideal to use here, but the amount of data passed to each block
                                 // is decided by dispatch_io_read, and we'd need to chunk it up to fit in the buffer anyways
                                 // still, might be better for cancellation
                                 // ACTUALLY maybe it can be specified, via the high/low watermark

                                 // and dispatch_io_set_interval should help with stalling to cancel

                                 // data has been read into dispatch_data_t data
                                 // this will be executed on _socketQueue
                                 // now loop over the data in sizes smaller than the buffer
                                 size_t buffered_chunk_size = MIN(cBufferSize, dispatch_data_get_size(data));
                                 size_t offset = 0;
                                 const void *buffer;
                                 while (   (buffered_chunk_size > 0)
                                        && (offset < dispatch_data_get_size(data))
                                        && request.isCancelled == NO) {
                                     dispatch_data_t buffered_chunk_subrange = dispatch_data_create_subrange(data, offset, buffered_chunk_size);
                                     size_t bytes_read = 0;
                                     // map the subrange to make sure we have a contiguous buffer
                                     dispatch_data_t mapped_buffered_chunk_subrange = dispatch_data_create_map(buffered_chunk_subrange, &buffer, &bytes_read);

                                     // send the buffer
                                     while (   request.isCancelled == NO
                                            && (sftp_result = libssh2_sftp_write(handle, buffer, bytes_read)) == LIBSSH2SFTP_EAGAIN) {
                                         // update shouldcontinue into the waitsocket file desctiptor
                                         waitsocket(socketFD, session);
                                     }
                                    #if NEEDS_DISPATCH_RETAIN_RELEASE
                                    dispatch_release(buffered_chunk_subrange);
                                    #endif
                                     mapped_buffered_chunk_subrange = NULL;
                                     
                                     offset += bytes_read;

                                     if (sftp_result > 0) {
                                         dispatch_source_merge_data(progressSource, sftp_result);
                                     } else {
                                         // error in SFTP write
                                         dispatch_async(_fileIOQueue, channel_cleanup_block);
                                     }
                                 }
                                 // end of reading while loop in dispatch_io_handler
                                 read_error = error;
                                 if (done) {
                                     dispatch_async(_fileIOQueue, channel_cleanup_block);
                                 }
                             }); // end of dispatch_io_read
        }); // end of _fileIOQueue
    }); // end of socketQueue
    return request;
}


@end

// waitsocket from http://www.libssh2.org/examples/

int waitsocket(int socket_fd, LIBSSH2_SESSION *session) {
    struct timeval timeout;
    int rc;
    fd_set fd;
    fd_set *writefd = NULL;
    fd_set *readfd = NULL;
    int dir;

    timeout.tv_sec = 10;
    timeout.tv_usec = 0;

    FD_ZERO(&fd);

    FD_SET(socket_fd, &fd);

    /* now make sure we wait in the correct direction */
    dir = libssh2_session_block_directions(session);

    if(dir & LIBSSH2_SESSION_BLOCK_INBOUND)
        readfd = &fd;

    if(dir & LIBSSH2_SESSION_BLOCK_OUTBOUND)
        writefd = &fd;

    rc = select(socket_fd + 1, readfd, writefd, NULL, &timeout);

    return rc;
}


// callback function for keyboard-interactive authentication
static void response(const char *name,
                     int name_len,
                     const char *instruction,
                     int instruction_len,
                     int num_prompts,
                     const LIBSSH2_USERAUTH_KBDINT_PROMPT *prompts,
                     LIBSSH2_USERAUTH_KBDINT_RESPONSE *responses,
                     void **abstract) {
    DLSFTPConnection *connection = (__bridge DLSFTPConnection *)*abstract;

    if (num_prompts > 0) {
        // check if prompt is password
        // assume responses matches prompts
        // according to documentation, string values will be free'd
        const char *password = [connection.password UTF8String];
        responses[0].text = malloc(strlen(password) * sizeof(char) + 1);
        strcpy(responses[0].text, password);
        responses[0].length = strlen(password);
    }
}

