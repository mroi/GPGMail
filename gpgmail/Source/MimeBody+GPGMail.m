/* MimeBody+GPGMail.m created by stephane on Thu 06-Jul-2000 */

/*
 * Copyright (c) 2000-2011, GPGTools Project Team <gpgtools-devel@lists.gpgtools.org>
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of GPGTools Project Team nor the names of GPGMail
 *       contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE GPGTools Project Team ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE GPGTools Project Team BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>
#import <Libmacgpg/Libmacgpg.h>
#import "CCLog.h"
#import "NSObject+LPDynamicIvars.h"
#import "NSData+GPGMail.h"
//#import "Message.h"
//#import "MessageStore.h"
//#import "MimeBody.h"
#import "Message+GPGMail.h"
#import "MimeBody+GPGMail.h"
#import "MimePart+GPGMail.h"

#import "GMMessageSecurityFeatures.h"

#define MAIL_SELF ((MCMimeBody *)self)

const static NSString *kMessageSecurityFeaturesKey = @"MessageSecurityFeaturesKey";
const NSString *kMimeBodyMessageKey = @"MimeBodyMessageKey";

@interface MimeBody_GPGMail (NotImplemented)

- (id)messageDataIncludingFromSpace:(BOOL)arg1 newDocumentID:(id)arg2 fetchIfNotAvailable:(BOOL)arg3;

@end

@implementation MimeBody_GPGMail

- (BOOL)MAIsSignedByMe {
    // This method tries to check the
    // signatures internally, if some are set.
    // This results in a crash, since Mail.app
    // can't handle GPGSignature signatures.
    GMMessageSecurityFeatures *securityProperties = [self securityFeatures];
    NSArray *messageSigners = [securityProperties PGPSignatures];
    if([messageSigners count] && [messageSigners[0] isKindOfClass:[GPGSignature class]]) {
        return YES;
    }
    // Otherwise call the original method.
    BOOL ret = [self MAIsSignedByMe];
    return ret;
}

/**
 It's not exactly clear when this method is used, but internally it
 checks the message for mime parts signaling S/MIME encrypted or signed
 messages.
 
 It can't be bad to fix it for PGP messages, anyway.
 Instead of the mime parts, which due to inline PGP are not reliable enough,
 GPGMail checks for PGP armor, which is included in inline and PGP/MIME messages.
 
 Apparently 
 
 */
- (BOOL)MA_isPossiblySignedOrEncrypted {
    // Check if message should be processed (-[Message shouldBePGPProcessed] - Snippet generation check)
    // otherwise out of here!
    if(![(Message_GPGMail *)[self message] shouldBePGPProcessed])
        return [self MA_isPossiblySignedOrEncrypted];
    
    return [self MA_isPossiblySignedOrEncrypted];
}

// TODO: Fix this, since on older versions this will create a crash.
- (id)message {
    return [self getIvar:kMimeBodyMessageKey];
}

- (NSData *)MAParsedMessage {
    DebugLog(@"Has message? %@", [self getIvar:kMimeBodyMessageKey]);
    id parsedMessage = [self MAParsedMessage];
    [parsedMessage setIvar:kMimeBodyMessageKey value:[self getIvar:kMimeBodyMessageKey]];
    
    [self collectSecurityFeatures];
    [parsedMessage setIvar:kMessageSecurityFeaturesKey value:[self securityFeatures]];
    
    return parsedMessage;
}

- (void)collectSecurityFeatures {
    // Collect the security parse result.
    GMMessageSecurityFeatures *securityFeatures = [GMMessageSecurityFeatures securityFeaturesFromMimeBody:self];
    // TODO: What to do if the security features are already set?
    [self setSecurityFeatures:securityFeatures];
    [[self getIvar:kMimeBodyMessageKey] setIvar:kMessageSecurityFeaturesKey value:securityFeatures];
}

- (void)setSecurityFeatures:(GMMessageSecurityFeatures *)securityFeatures {
    [self setIvar:kMessageSecurityFeaturesKey value:securityFeatures];
}

- (GMMessageSecurityFeatures *)securityFeatures {
    return [self getIvar:kMessageSecurityFeaturesKey];
}

@end

#undef MAIL_SELF

