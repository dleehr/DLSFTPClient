//
//  NSDictionary+SFTPFileAttributes.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/12/12.
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

#import "NSDictionary+SFTPFileAttributes.h"

NSString const * DLFileAccessDate = @"DLFileAccessDate";

@implementation NSDictionary (SFTPFileAttributes)

+ (NSDictionary *)dictionaryWithAttributes:(LIBSSH2_SFTP_ATTRIBUTES)attributes {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    // filetype indicates file/dir/symlink
    // need to check if permissions is in flags first
    if (attributes.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) {
        [dictionary setObject:@(attributes.permissions) forKey:NSFilePosixPermissions];

        if (LIBSSH2_SFTP_S_ISDIR(attributes.permissions)) {
            [dictionary setObject:NSFileTypeDirectory forKey:NSFileType];
        } else if(LIBSSH2_SFTP_S_ISREG(attributes.permissions)) {
            [dictionary setObject:NSFileTypeRegular forKey:NSFileType];
        } else if(LIBSSH2_SFTP_S_ISLNK(attributes.permissions)) {
            [dictionary setObject:NSFileTypeSymbolicLink forKey:NSFileType];
        } else if(LIBSSH2_SFTP_S_ISCHR(attributes.permissions)) {
            [dictionary setObject:NSFileTypeCharacterSpecial forKey:NSFileType];
        } else if(LIBSSH2_SFTP_S_ISBLK(attributes.permissions)) {
            [dictionary setObject:NSFileTypeBlockSpecial forKey:NSFileType];
        } else if(LIBSSH2_SFTP_S_ISSOCK(attributes.permissions)) {
            [dictionary setObject:NSFileTypeSocket forKey:NSFileType];
        }
    }
    if (attributes.flags & LIBSSH2_SFTP_ATTR_SIZE) {
        [dictionary setObject:@(attributes.filesize) forKey:NSFileSize];
    }
    
    if (attributes.flags & LIBSSH2_SFTP_ATTR_UIDGID) {
        [dictionary setObject:@(attributes.uid) forKey:NSFileOwnerAccountID];
        [dictionary setObject:@(attributes.gid) forKey:NSFileGroupOwnerAccountID];
    }

    if (attributes.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) {
        NSDate *modificationDate = [NSDate dateWithTimeIntervalSince1970:attributes.mtime];
        [dictionary setObject:modificationDate forKey:NSFileModificationDate];
        NSDate *accessDate = [NSDate dateWithTimeIntervalSince1970:attributes.atime];
        [dictionary setObject:accessDate forKey:DLFileAccessDate];
    }

    return dictionary;
}

@end
