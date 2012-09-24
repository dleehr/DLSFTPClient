//
//  NSDictionary+SFTPFileAttributes.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/12/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import "NSDictionary+SFTPFileAttributes.h"

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

    if (attributes.flags & LIBSSH2_SFTP_ATTR_PERMISSIONS) {
    }

    if (attributes.flags & LIBSSH2_SFTP_ATTR_ACMODTIME) {
        [dictionary setObject:@(attributes.mtime) forKey:NSFileModificationDate];

    }
    return dictionary;

}


@end
