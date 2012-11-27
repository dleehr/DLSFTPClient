//
//  DLSFTPFile.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/11/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

NSString * const DLSFTPFilePathKey = @"DLSFTPFilePath";
NSString * const DLSFTPFileAttributesKey = @"DLSFTPFileAttributes";

#import "DLSFTPFile.h"

@implementation DLSFTPFile

- (id)initWithPath:(NSString *)path
        attributes:(NSDictionary *)attributes {
    self = [super init];
    if (self) {
        _path = [path copy];
        _attributes = [attributes copy];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"name: %@ attributes %@"
            , [self filename]
            , self.attributes];
}

- (NSComparisonResult)compare:(DLSFTPFile *)otherFile {
    return [self.path compare:otherFile.path];
}

- (NSString *)filename {
    return [self.path lastPathComponent];
}

- (BOOL)isEqual:(id)object {
    if (object == self) {
        return YES;
    } else if ([object isKindOfClass:[DLSFTPFile class]]) {
        DLSFTPFile *otherFile = (DLSFTPFile *)object;
        return [self.path isEqualToString:otherFile.path];
    } else {
        return NO;
    }
}

- (NSUInteger)hash {
    NSUInteger prime = 31;
    NSUInteger result = 1;
    result = prime * result + [self.attributes hash];
    result = prime * result + [self.path hash];
    return result;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super init];
    if (self) {
        _path = [[aDecoder decodeObjectForKey:DLSFTPFilePathKey] copy];
        _attributes = [[aDecoder decodeObjectForKey:DLSFTPFileAttributesKey] copy];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:self.path forKey:DLSFTPFilePathKey];
    [aCoder encodeObject:self.attributes forKey:DLSFTPFileAttributesKey];
}

@end;
