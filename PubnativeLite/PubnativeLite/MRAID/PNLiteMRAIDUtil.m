//
//  Copyright © 2018 PubNative. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "PNLiteMRAIDUtil.h"

@implementation PNLiteMRAIDUtil

+ (NSString *)processRawHtml:(NSString *)rawHtml {
    NSString *processedHtml = rawHtml;
    NSRange range;
    
    // Remove the mraid.js script tag.
    // We expect the tag to look like this:
    // <script src='mraid.js'></script>
    // But we should also be to handle additional attributes and whitespace like this:
    // <script  type = 'text/javascript'  src = 'mraid.js' > </script>
    
    NSString *pattern = @"<script\\s+[^>]*\\bsrc\\s*=\\s*([\\\"\\\'])mraid\\.js\\1[^>]*>\\s*</script>\\n*";
    NSError *error = NULL;
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    processedHtml = [regex stringByReplacingMatchesInString:processedHtml
                                                    options:0
                                                      range:NSMakeRange(0, [processedHtml length])
                                               withTemplate:@""];
    
    // Add html, head, and/or body tags as needed.
    range = [rawHtml rangeOfString:@"<html"];
    BOOL hasHtmlTag = (range.location != NSNotFound);
    range = [rawHtml rangeOfString:@"<head"];
    BOOL hasHeadTag = (range.location != NSNotFound);
    range = [rawHtml rangeOfString:@"<body"];
    BOOL hasBodyTag = (range.location != NSNotFound);
    
    // basic sanity checks
    if ((!hasHtmlTag && (hasHeadTag || hasBodyTag)) ||
        (hasHtmlTag && !hasBodyTag)) {
        return nil;
    }
    
    if (!hasHtmlTag) {
        processedHtml = [NSString stringWithFormat:
                         @"<html>\n"
                         "<head>\n"
                         "</head>\n"
                         "<body>\n"
                         "<div align='center'>\n"
                         "%@"
                         "</div>\n"
                         "</body>\n"
                         "</html>",
                         processedHtml
                         ];
    } else if (!hasHeadTag) {
        // html tag exists, head tag doesn't, so add it
        pattern = @"<html[^>]*>";
        error = NULL;
        regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        processedHtml = [regex stringByReplacingMatchesInString:processedHtml
                                                        options:0
                                                          range:NSMakeRange(0, [processedHtml length])
                                                   withTemplate:@"$0\n<head>\n</head>"];
    }
    
    // Add meta and style tags to head tag.
    NSString *metaTag =
    @"<meta name='viewport' content='width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no' />";
    
    NSString *styleTag =
    @"<style>\n"
    "body { margin:0; padding:0; }\n"
    "*:not(input) { -webkit-touch-callout:none; -webkit-user-select:none; -webkit-text-size-adjust:none; }\n"
    "</style>";
    
    pattern = @"<head[^>]*>";
    error = NULL;
    regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                      options:NSRegularExpressionCaseInsensitive
                                                        error:&error];
    processedHtml = [regex stringByReplacingMatchesInString:processedHtml
                                                    options:0
                                                      range:NSMakeRange(0, [processedHtml length])
                                               withTemplate:[NSString stringWithFormat:@"$0\n%@\n%@", metaTag, styleTag]];
    
    return processedHtml;
}

@end
