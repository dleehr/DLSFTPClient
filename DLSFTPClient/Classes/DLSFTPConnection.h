//
//  DLSFTPConnection.h
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

#import <Foundation/Foundation.h>
#import "DLSFTP.h"

@class DLSFTPFile;
@class DLSFTPRequest;

int waitsocket(int socket_fd, LIBSSH2_SESSION *session);

@interface DLSFTPConnection : NSObject <DLSFTPRequestDelegate>

@property (nonatomic, strong, readonly) dispatch_queue_t socketQueue;

#pragma mark Connection

- (id)initWithHostname:(NSString *)hostname
                  port:(NSUInteger)port
              username:(NSString *)username
              password:(NSString *)password;

- (id)initWithHostname:(NSString *)hostname
              username:(NSString *)username
              password:(NSString *)password;

- (id)initWithHostname:(NSString *)hostname
                  port:(NSUInteger)port
              username:(NSString *)username
               keypath:(NSString *)keypath
            passphrase:(NSString *)passphrase;

- (id)initWithHostname:(NSString *)hostname
              username:(NSString *)username
               keypath:(NSString *)keypath
            passphrase:(NSString *)passphrase;

- (void)connectWithSuccessBlock:(DLSFTPClientSuccessBlock)successBlock
                   failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (void)disconnect;
- (void)cancelAllRequests;
- (BOOL)isConnected;

# pragma mark - Request

- (NSUInteger)requestCount;
- (void)submitRequest:(DLSFTPRequest *)request;
- (void)removeRequest:(DLSFTPRequest *)request;

@end
