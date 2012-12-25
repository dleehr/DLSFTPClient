//
//  DLFileSizeFormatter.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/19/12.
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

#import "DLFileSizeFormatter.h"

@interface DLFileSizeFormatter () {
    NSNumberFormatter *_formatter;
}

@end

@implementation DLFileSizeFormatter

- (id)init {
    self = [super init];
    if (self) {
        _formatter = [[NSNumberFormatter alloc] init];
        _formatter.locale = [NSLocale currentLocale];
        _formatter.numberStyle = NSNumberFormatterDecimalStyle;
        _formatter.maximumFractionDigits = 2;
    }
    return self;
}

- (NSString *)stringFromSize:(unsigned long long)size {
    int exponent = 0;
    unsigned long long tmpsize = size;

    while (tmpsize >>= 1)  {
        ++exponent;
    }

    double sizeDouble = size;

    NSString *units = @"B";
    if ((exponent >= 10) && (exponent < 20)) {
        units = @"KB";
        sizeDouble = sizeDouble / (1llu << 10);
    } else if ((exponent >= 20) && (exponent < 30)) {
        units = @"MB";
        sizeDouble = sizeDouble / (1llu << 20);
    } else if (exponent >= 30) {
        units = @"GB";
        sizeDouble = sizeDouble / (1llu << 30);
    }

    NSString *formattedNumber = [_formatter stringFromNumber:@(sizeDouble)];
    return [NSString stringWithFormat:@"%@ %@", formattedNumber, units];
}

@end
