//
//  NSDictionary+SFTPFileAttributes.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/12/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#include "libssh2_sftp.h"
#import <Foundation/Foundation.h>

@interface NSDictionary (SFTPFileAttributes)

+ (NSDictionary *)dictionaryWithAttributes:(LIBSSH2_SFTP_ATTRIBUTES)attributes;

@end
