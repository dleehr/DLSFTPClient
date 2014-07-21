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
#import "DLSFTPConnection.h"
#import "DLSFTPRequest.h"
#import <CFNetwork/CFNetwork.h>

// disconnection callback
LIBSSH2_DISCONNECT_FUNC(disconnected);

// keyboard-interactive response
LIBSSH2_USERAUTH_KBDINT_RESPONSE_FUNC(response);

NSString * const SFTPClientErrorDomain = @"SFTPClientErrorDomain";
NSString * const SFTPClientUnderlyingErrorKey = @"SFTPClientUnderlyingError";

static const NSUInteger cDefaultSSHPort = 22;
static const NSTimeInterval cDefaultConnectionTimeout = 15.0;
static const NSTimeInterval cIdleTimeout = 60.0;
static NSString * const SFTPClientCompleteRequestException = @"SFTPClientCompleteRequestException";


@interface DLSFTPConnection () {

    // request queue
    dispatch_queue_t _requestQueue;

    // connection group
    dispatch_group_t _connectionGroup;

    // idle timer
    dispatch_source_t _idleTimer;

    // socket source
    dispatch_source_t _writeSource;
}

// socket queue, needed by requests
@property (nonatomic, strong, readwrite) dispatch_queue_t socketQueue;

@property (nonatomic, copy) DLSFTPClientSuccessBlock connectionSuccessBlock;
@property (nonatomic, copy) DLSFTPClientFailureBlock connectionFailureBlock;

@property (nonatomic, copy) NSString *username;
@property (nonatomic, copy) NSString *password;
@property (nonatomic, copy) NSString *keypath;
@property (nonatomic, copy) NSString *hostname;
@property (nonatomic, assign) NSUInteger port;

@property (nonatomic, assign) int socket;
@property (nonatomic, strong) dispatch_source_t timeoutTimer;
@property (nonatomic, assign) LIBSSH2_SESSION *session;
@property (nonatomic, assign) LIBSSH2_SFTP *sftp;

// Request handling
@property (nonatomic, strong) NSMutableArray *requests;
@property (nonatomic, strong) DLSFTPRequest *currentRequest;
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
        self.socketQueue = dispatch_queue_create("com.hammockdistrict.SFTPClient.socket", DISPATCH_QUEUE_SERIAL);
        _requestQueue = dispatch_queue_create("com.hammockdistrict.SFTPClient.request", DISPATCH_QUEUE_CONCURRENT);
        _connectionGroup = dispatch_group_create();
        _idleTimer = NULL; // lazily loaded
    }
    return self;
}

- (void)dealloc {
    [self _disconnect];
    #if NEEDS_DISPATCH_RETAIN_RELEASE
    dispatch_release(_requestQueue);
    _requestQueue = NULL;
    dispatch_release(_socketQueue);
    _socketQueue = NULL;
    dispatch_release(_connectionGroup);
    _connectionGroup = NULL;
    if (_idleTimer) {
        dispatch_release(_idleTimer);
        _idleTimer = NULL;
    }
    #endif
}

- (dispatch_queue_t)requestQueue {
    return _requestQueue;
}
- (dispatch_source_t)writeSource {
    return _writeSource;
}

- (dispatch_source_t)idleTimer {
    if (_idleTimer == NULL) {
        _idleTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
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

- (void)disconnectSession {
    if (_session) {
        // this implies SSH_DISCONNECT_BY_APPLICATION
        while (libssh2_session_disconnect(_session, "") == LIBSSH2_ERROR_EAGAIN) {
            waitsocket(self.socket, _session);
        }
        while (libssh2_session_free(_session) == LIBSSH2_ERROR_EAGAIN) {
            waitsocket(self.socket, _session);
        }
        self.session = NULL;
    }
}

- (LIBSSH2_SESSION *)session {
    if (_session == NULL) {
        _session = libssh2_session_init_ex(NULL, NULL, NULL, (__bridge void *)self);
        // set non-blocking
        if (_session) {
            libssh2_session_set_blocking(_session, 0);
            libssh2_session_callback_set(_session, LIBSSH2_CALLBACK_DISCONNECT, disconnected);
        }
    }
    return _session;
}

- (void)shutdownSftp {
    if (_sftp) {
        while (libssh2_sftp_shutdown(_sftp) == LIBSSH2SFTP_EAGAIN) {
            waitsocket(self.socket, _session);
        }
        self.sftp = NULL;
    }
}

// If there's an error initializing sftp, such as a non-authenticated connection, this will return NULL and we must check the session error
- (LIBSSH2_SFTP *)sftp {
    if (_sftp == NULL) {
        LIBSSH2_SESSION *session = self.session;
        // initialize sftp in non-blocking
        // Hack to limit the number of tries here, because
        // hosts without SFTP trigger an infinite loop
        int retries = 0, max = 10;
        while (   (_sftp = libssh2_sftp_init(session)) == NULL
               && (libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN)
               && (retries++ < max)) {
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

- (void)_disconnect {
    if (_idleTimer) { // avoid cancelling after dealloc
        [self cancelIdleTimer];
    }
    if (_writeSource && dispatch_source_testcancel(_writeSource) == 0) {
        dispatch_source_cancel(_writeSource);
    }
    [self shutdownSftp];
    [self disconnectSession];
    if (self.socket >= 0) {
        if(close(self.socket) == -1) {
            NSLog(@"Error closing socket: %d", errno);
        }
        self.socket = -1;
    }
}

// called by the disconnect handler when a SSH_MSG_DISCONNECT is received
// not called when SSH_DISCONNECT_BY_APPLICATION
- (void)disconnectedWithReason:(NSInteger)reason message:(NSString *)message {
    [self shutdownSftp];
    // don't call disconnectSession because it is already disconnected
    while (libssh2_session_free(_session) == LIBSSH2_ERROR_EAGAIN) {
        waitsocket(self.socket, _session);
    }
    [self cancelAllRequests];
    if (self.connectionFailureBlock) {
        NSString *errorDescription = [NSString stringWithFormat:@"Disconnected with reason %ld: %@", (long)reason, message];
        [self failConnectionWithErrorCode:eSFTPClientErrorDisconnected
                         errorDescription:errorDescription];
    }
    [self clearConnectionBlocks];
}

- (void)startSFTPSession {
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_group_async(_connectionGroup, self.socketQueue, ^{
        int socketFD = self.socket;
        LIBSSH2_SESSION *session = self.session;

        if (session == NULL) { // unable to access the session
            // close the socket
            [weakSelf _disconnect];
            // unable to initialize session
            [weakSelf failConnectionWithErrorCode:eSFTPClientErrorUnableToInitializeSession
                   errorDescription:@"Unable to initialize libssh2 session"];
            weakSelf.connectionSuccessBlock = nil;
            return;
        }
        // valid session, get the socket descriptor
        // must be called from socket's queue
        long result;
        while (   (result = libssh2_session_handshake(session, socketFD) == LIBSSH2_ERROR_EAGAIN)
               && weakSelf.isConnected) {
            waitsocket(socketFD, session);
        }
        if (result) {
            // handshake failed
            // free the session and close the socket
            [weakSelf _disconnect];

            NSString *errorDescription = [NSString stringWithFormat:@"Handshake failed with code %ld", result];
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
            [weakSelf _disconnect];
            NSString *errorDescription = [NSString stringWithFormat:@"Authentication failed with code %ld", result];
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

- (void)submitRequest:(DLSFTPRequest *)request {
    request.connection = self;
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_barrier_async(_requestQueue, ^{
        [weakSelf.requests addObject:request];
        [weakSelf cancelIdleTimer];
        [weakSelf startNextRequest];
    });
}

- (void)removeRequest:(DLSFTPRequest *)request {
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
        } else {
            // start the idle timer
            [weakSelf startIdleTimer];
        }
    });
}

- (void)startRequest {
    DLSFTPRequest *request = self.currentRequest;
    dispatch_group_notify(_connectionGroup, self.socketQueue, ^{
        [request start];
    });
}

- (void)finishRequest:(DLSFTPRequest *)request failed:(BOOL)failed {
    if (   self.currentRequest == nil
        || [self.currentRequest isEqual:request] == NO) {
        [NSException raise:SFTPClientCompleteRequestException
                    format:@"Exception completing request %@, it is not the current request %@" , request, self.currentRequest];
        return;
    }
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_group_notify(_connectionGroup, self.socketQueue, ^{
        if (failed) {
            [request fail];
        } else {
            [request succeed];
        }
        weakSelf.currentRequest = nil;
        [weakSelf startNextRequest];
    });

}

- (void)requestDidFail:(DLSFTPRequest *)request withError:(NSError *)error {
    // error is also retained by the request, so is superfluous here
    [self finishRequest:request failed:YES];
}

- (void)requestDidComplete:(DLSFTPRequest *)request {
    [self finishRequest:request failed:NO];
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

#pragma mark Public

- (void)cancelAllRequests {
    __weak DLSFTPConnection *weakSelf = self;
    [self.currentRequest cancel];
    dispatch_barrier_sync(_requestQueue, ^{
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
    return count;
}

// just if the socket is connected
- (BOOL)isConnected {
    return self.socket >= 0;
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
    if ([self.hostname length] == 0) {
        [self failConnectionWithErrorCode:eSFTPClientErrorInvalidHostname
                         errorDescription:@"Invalid hostname"];
        return;
    } else if([self.username length] == 0) {
        [self failConnectionWithErrorCode:eSFTPClientErrorInvalidUsername
                         errorDescription:@"Invalid username"];
        return;

    } else if([self.password length] == 0 && [self.keypath length] == 0) {
        [self failConnectionWithErrorCode:eSFTPClientErrorInvalidPasswordOrKey
                         errorDescription:@"Invalid password or key path"];
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
        dispatch_source_t timeoutTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                                dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
        self.timeoutTimer = timeoutTimer;
        dispatch_source_set_event_handler(timeoutTimer, ^{
            [weakSelf timeoutTimerHandler];
        });

        // On cancel, release the timer if necessary
        dispatch_source_set_cancel_handler(timeoutTimer, ^{
            if (weakSelf.timeoutTimer) {
                #if NEEDS_DISPATCH_RETAIN_RELEASE
                dispatch_release(weakSelf.timeoutTimer);
                #endif
                weakSelf.timeoutTimer = NULL;
            }
        });

        // Resume the timer but don't set its fire time until we're about to try connecting
        dispatch_source_set_timer(timeoutTimer, DISPATCH_TIME_FOREVER, DISPATCH_TIME_FOREVER, 0);
        if (timeoutTimer) {
            dispatch_resume(timeoutTimer);
        }

        // initialize and connect the socket on the socket queue
        dispatch_group_async(_connectionGroup, self.socketQueue, ^{
            // Resolve the hostname

            CFHostRef hostRef = CFHostCreateWithName(NULL, (__bridge CFStringRef)(weakSelf.hostname));
            Boolean resolved = CFHostStartInfoResolution(hostRef, kCFHostAddresses, NULL);
            if (!resolved) {
                CFRelease(hostRef);
                [weakSelf failConnectionWithErrorCode:eSFTPClientErrorUnableToResolveHostname
                                     errorDescription:@"Unable to resolve hostname"];
                return;
            }
            // Get resolved address
            Boolean hasBeenResolved = false;
            NSArray *addresses = (__bridge NSArray *)CFHostGetAddressing(hostRef, &hasBeenResolved);

            if (addresses == NULL) {
                CFRelease(hostRef);

                [weakSelf failConnectionWithErrorCode:eSFTPClientErrorUnableToResolveHostname
                                     errorDescription:@"Unable to obtain an address for hostname"];
                return;
            }
            CFRelease(hostRef);
            // Get a connection
            [weakSelf connectToAddressAtIndex:0 inArray:addresses];
        });
    }
}

- (void)connectToAddressAtIndex:(NSUInteger)index inArray:(NSArray *)addresses {
    if (index >= [addresses count]) {
        [self _disconnect];
        [self failConnectionWithErrorCode:eSFTPClientErrorUnableToConnect
                         errorDescription:@"Unable to connect"];
        self.connectionSuccessBlock = nil;
        return;
    }
    __weak DLSFTPConnection *weakSelf = self;
    NSData *addressData = [addresses objectAtIndex:index];
    int result = -1;
    struct sockaddr *soin = NULL;
    socklen_t soin_size = 0;
    struct sockaddr_in soin4;
    struct sockaddr_in6 soin6;
    if ([addressData length] == sizeof(struct sockaddr_in)) {
        // IPv4 address
        [addressData getBytes:&soin4 length:sizeof(soin4)];
        soin4.sin_port = htons(self.port);
        soin_size = sizeof(soin4);
        soin = (struct sockaddr*)(&soin4);
    } else if([addressData length] == sizeof(struct sockaddr_in6)) {
        // IPv6 address
        [addressData getBytes:&soin6 length:sizeof(soin6)];
        soin6.sin6_port = htons(self.port);
        soin_size = sizeof(soin6);
        soin = (struct sockaddr*)(&soin6);
    } else {
        // Unknown address length
        dispatch_group_async(_connectionGroup, self.socketQueue, ^{
            [weakSelf connectToAddressAtIndex:index + 1
                                      inArray:addresses];
        });
        return;
    }
    // restart the timer
    dispatch_time_t fireTime = dispatch_time(DISPATCH_TIME_NOW, cDefaultConnectionTimeout * NSEC_PER_SEC);
    if (self.timeoutTimer) {
        dispatch_source_set_timer(self.timeoutTimer, fireTime, DISPATCH_TIME_FOREVER, 0);
    }

    // Create a socket
    int sock = socket(soin->sa_family, SOCK_STREAM, 0);

    int set = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, (void *)&set, sizeof(int));

    // Configure socket for non-blocking
    int existingFlags = fcntl(sock, F_GETFL);
    int flags = fcntl(sock, F_SETFL, existingFlags | O_NONBLOCK);
    if (flags) {
        close(sock);
        [self failConnectionWithErrorCode:eSFTPClientErrorSocketError
                         errorDescription:@"Unable to configure socket connection for non-blocking"];
        self.connectionSuccessBlock = nil;
        return;
    }

    if (sock == -1) { // no socket
        [self failConnectionWithErrorCode:eSFTPClientErrorSocketError
                         errorDescription:@"Unable to create socket"];
        self.connectionSuccessBlock = nil;
        return;
    }

    // set up a dispatch source to monitor the socket fd
    _writeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_WRITE, sock, 0, self.socketQueue);
    dispatch_group_t connectionGroup = _connectionGroup;
    dispatch_block_t connected_handler = ^{
        if (weakSelf.timeoutTimer) {
            dispatch_source_cancel(weakSelf.timeoutTimer);
        }
        [weakSelf startSFTPSession];
    };
    // enter the connectionGroup explicitly to keep the group alive while waiting for the dispatch source
    dispatch_group_enter(connectionGroup);
    dispatch_block_t sock_handler = ^{
        int error;
        socklen_t len = sizeof(error);
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &error, &len);
        if (error) {
            // try the next address
            close(sock);
            DLSFTPConnection *strongSelf = weakSelf;
            if (strongSelf) {
                // Cannot dispatch to NULL queue
                dispatch_group_async(connectionGroup, strongSelf.socketQueue, ^{
                    [strongSelf connectToAddressAtIndex:index + 1
                                                inArray:addresses];
                });
            }
        } else {
            weakSelf.socket = sock;
            dispatch_source_t writeSource = [weakSelf writeSource];
            if (writeSource && dispatch_source_testcancel(writeSource) == 0) {
                dispatch_source_cancel(writeSource);
            }
            DLSFTPConnection *strongSelf = weakSelf;
            if (strongSelf) {
                dispatch_group_async(connectionGroup, strongSelf.socketQueue, connected_handler);
            }
        }
    };

    dispatch_source_set_event_handler(_writeSource, sock_handler);
    dispatch_source_set_cancel_handler(_writeSource, ^{
        DLSFTPConnection *strongSelf = weakSelf;
        if (strongSelf && strongSelf->_writeSource) {
            #if NEEDS_DISPATCH_RETAIN_RELEASE
            dispatch_release(strongSelf->_writeSource);
            #endif
            strongSelf->_writeSource = NULL;
        }
        dispatch_group_leave(connectionGroup);
    });

    // Update the timeout timer to cancel the dispatch source
    if (self.timeoutTimer) {
        dispatch_source_set_event_handler(self.timeoutTimer, ^{
            dispatch_source_t writeSource = [weakSelf writeSource];
            if (writeSource && dispatch_source_testcancel(writeSource) == 0) {
                dispatch_source_cancel(writeSource);
            }
            [weakSelf timeoutTimerHandler];
        });
    }
    dispatch_resume(_writeSource);

    // connect result
    result = connect(sock, soin, soin_size);
    if (result == 0) {
        // connected immediately
        dispatch_group_async(connectionGroup, self.socketQueue, connected_handler);
    } else if (errno == EINPROGRESS || errno == EALREADY) {
        // connecting, wait for the handler to be called and leave the dispatch group
        return;
    } else {
        // error, close this socket and try the next address
        close(sock);
        dispatch_group_async(connectionGroup, self.socketQueue, ^{
            [weakSelf connectToAddressAtIndex:index + 1
                                      inArray:addresses];
        });
    }
}

- (void)timeoutTimerHandler {
    // timeout fired, close the socket
    __weak DLSFTPConnection *weakSelf = self;
    dispatch_sync(self.socketQueue, ^{
        [weakSelf _disconnect]; // closes on socketQueue
    });
    // and fail
    [self failConnectionWithErrorCode:eSFTPClientErrorConnectionTimedOut
                     errorDescription:@"Connection timed out"];
    // clear out the queued success block
    self.connectionSuccessBlock = nil;
    if (self.timeoutTimer) {
        dispatch_source_cancel(self.timeoutTimer);
    }
}

- (void)disconnect {
    [self cancelAllRequests];
    // cancel the connection timeout timer if running
    if (self.timeoutTimer) {
        dispatch_source_cancel(self.timeoutTimer);
    }
    dispatch_sync(self.socketQueue, ^{
        [self _disconnect];
    });
    if (self.connectionFailureBlock) { // not yet connected
        [self failConnectionWithErrorCode:eSFTPClientErrorCancelledByUser
                         errorDescription:@"Cancelled by user"];
    }
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
LIBSSH2_USERAUTH_KBDINT_RESPONSE_FUNC(response) {
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

// callback function for disconnect
LIBSSH2_DISCONNECT_FUNC(disconnected) {
    DLSFTPConnection *connection = (__bridge DLSFTPConnection *)(*abstract);
    if (connection) {
        dispatch_async(connection.socketQueue, ^{
            [connection disconnectedWithReason:reason message:[NSString stringWithUTF8String:message]];
        });
    }
}
