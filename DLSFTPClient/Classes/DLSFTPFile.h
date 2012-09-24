//
//  DLSFTPFile.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/11/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import <Foundation/Foundation.h>
@interface DLSFTPFile : NSObject

- (id)initWithPath:(NSString *)path
        attributes:(NSDictionary *)attributes;

@property (strong, nonatomic, readonly) NSString *path;
@property (strong, nonatomic, readonly) NSDictionary *attributes;

- (NSString *)filename;

@end
