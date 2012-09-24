//
//  DLFileSizeFormatter.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/19/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface DLFileSizeFormatter : NSObject

- (NSString *)stringFromSize:(unsigned long long)size;

@end
