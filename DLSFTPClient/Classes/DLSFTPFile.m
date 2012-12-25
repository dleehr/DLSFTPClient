//
//  DLSFTPFile.m
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
