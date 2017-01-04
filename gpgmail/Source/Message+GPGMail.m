/* Message+GPGMail.m created by Lukas Pitschl (@lukele) on Thu 18-Aug-2011 */

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

#import <objc/objc-runtime.h>
#import <Libmacgpg/Libmacgpg.h>
#import "NSObject+LPDynamicIvars.h"
#import "CCLog.h"
#import <MCMimePart.h>
#import <MCMimeBody.h>
#import "MFLibraryMessage.h"
//#import <MessageStore.h>
//#import <ActivityMonitor.h>
//#import "MFError.h"
//#import "MessageRouter.h"
#import "MimePart+GPGMail.h"
#import "Message+GPGMail.h"
#import "GPGMailBundle.h"
#import "NSString+GPGMail.h"
#import "GPGFlaggedString.h"

#import "GMMessageSecurityFeatures.h"

@interface MCMessage (NotImplemented)

- (id)messageDataIncludingFromSpace:(BOOL)arg1 newDocumentID:(id)arg2 fetchIfNotAvailable:(BOOL)arg3;

@end

@interface MCMimePart (NotImplemented)

- (id)initWithEncodedData:(id)arg1;
- (void)parse;
@end

#define mailself ((MCMessage *)self)

const static NSString *kMessageSecurityFeaturesKey = @"MessageSecurityFeaturesKey";
extern const NSString *kMimeBodyMessageKey;

@implementation Message_GPGMail

// TODO: Re-Implement the methods for sierra using security properties.
- (void)fakeMessageFlagsIsEncrypted:(BOOL)isEncrypted isSigned:(BOOL)isSigned {
    return;
//    unsigned int currentMessageFlags = [[self valueForKey:@"_messageFlags"] unsignedIntValue];
//    
//	if(isEncrypted)
//        currentMessageFlags |= 0x00000008;
//    if(isSigned)
//        currentMessageFlags |= 0x00800000;
//    
//    [self setValue:[NSNumber numberWithUnsignedInt:currentMessageFlags] forKey:@"_messageFlags"];
}

- (BOOL)isSigned {
    return ([mailself messageFlags] & 0x00800000) || self.securityFeatures.PGPSigned;
}

- (BOOL)isEncrypted {
    return ([mailself messageFlags] & 0x00000008) || self.securityFeatures.PGPSigned;
}

- (BOOL)isSMIMESigned {
    return ([mailself messageFlags] & 0x00800000) && !self.securityFeatures.PGPSigned;
}

- (BOOL)isSMIMEEncrypted {
    return ([mailself messageFlags] & 0x00000008) && !self.securityFeatures.PGPEncrypted;
}


- (BOOL)shouldBePGPProcessed {
    // Components are missing? What to do...
//    if([[GPGMailBundle sharedInstance] componentsMissing])
//        return NO;
    
    // OpenPGP is disabled for reading? Return false.
    if(![[GPGOptions sharedOptions] boolForKey:@"UseOpenPGPForReading"])
        return NO;
    
    // Message was actively selected by the user? PGP process message.
    if([self userDidActivelySelectMessageCheckingMessageOnly:YES])
        return YES;
    
    // If NeverCreatePreviewSnippets is set, return NO.
    if([[GPGOptions sharedOptions] boolForKey:@"NeverCreatePreviewSnippets"])
        return NO;
    
    // Message was not actively select and snippets should not be created?
    // Don't process the message and let's get on with it.
    return YES;
}

- (BOOL)userDidActivelySelectMessageCheckingMessageOnly:(BOOL)messageOnly {
	BOOL userDidSelectMessage = NO;
	// In some occasions this variable is not set, even though the user actively selected the message.
	// This issue has been seen with drafts. The reason seems to be, that the message object does
	// where the flag has been set, is not necessarily the same we're seeing in here.
	// As it turns out, while the message object is re-created, the messageBody object remains the same.
	// So let's check on the messageBody object as well.
	// Lesson learned: using messageBody forces the message body to be loaded.
	// Since we're only interested in the messageBody if it's already available, we use
	// messageBodyIfAvailable instead.
	// Another lesson learned: this leads to terrible problems, since the some body
	// methods, call shouldBePGPProcessed, which in turn calls this message again.
	// So in order to avoid a recursion, we don't check the body in all circumstances.
	// Update. Don't check the body, it still causes recursions sometimes.
	if([self getIvar:@"UserSelectedMessage"])
		userDidSelectMessage = [[self getIvar:@"UserSelectedMessage"] boolValue];
	
	return userDidSelectMessage;
}

- (BOOL)shouldCreateSnippetWithData:(NSData *)data {
    // CreatePreviewSnippets is set? Always return true.
    DebugLog(@"Create Preview snippets: %@", [[GPGOptions sharedOptions] boolForKey:@"CreatePreviewSnippets"] ? @"YES" : @"NO");
    DebugLog(@"User Selected Message: %@", [[self getIvar:@"UserSelectedMessage"] boolValue] ? @"YES" : @"NO");
	
	// Always *create snippet* (decrypt data) if the user actively selected the message.
	if([self userDidActivelySelectMessageCheckingMessageOnly:NO])
		return YES;
	
	// Since rule applying and snippet creation are connected, snippets are
	// created in classic view as well, but always only if the passphrase is in cache.
	// * none of the above and CreatePreviewSnippets preference is set -> create the snippet
	// * none of the above but passphrase for key is available (gpg-agent or keychain) -> create the snippet
	
	if([[GPGOptions sharedOptions] boolForKey:@"CreatePreviewSnippets"])
		return YES;
    
    // Otherwise check if the passphrase is already cached. If it is
    // return true, 'cause the user want be asked for the passphrase again.
    
    // The message could be encrypted to multiple subkeys.
    // All of the keys have to be in the cache.
    NSMutableSet *keyIDs = [[NSMutableSet alloc] initWithCapacity:0];
    
    NSArray *packets = nil;
    @try {
        packets = [GPGPacket packetsWithData:data];
    }
    @catch (NSException *exception) {
        return NO;
    }
    
	for (GPGPacket *packet in packets) {
		if (packet.tag == GPGPublicKeyEncryptedSessionKeyPacketTag) {
			GPGPublicKeyEncryptedSessionKeyPacket *keyPacket = (GPGPublicKeyEncryptedSessionKeyPacket *)packet;
			[keyIDs addObject:keyPacket.keyID];
		}
    }
    
	NSUInteger nrOfMatchingSecretKeys = 0;
	NSUInteger nrOfKeysWithPassphraseInCache = 0;
    GPGController *gpgc = [[GPGController alloc] init];
    
    for(NSString *keyID in keyIDs) {
        GPGKey *key = [[GPGMailBundle sharedInstance] secretGPGKeyForKeyID:keyID includeDisabled:YES];
        if(!key)
            continue;
		nrOfMatchingSecretKeys += 1;
		if([gpgc isPassphraseForKeyInCache:key]) {
			nrOfKeysWithPassphraseInCache += 1;
			DebugLog(@"Passphrase found in cache!");
        }
    }
    
	BOOL passphraseInCache = nrOfMatchingSecretKeys + nrOfKeysWithPassphraseInCache	!= 0 && nrOfMatchingSecretKeys == nrOfKeysWithPassphraseInCache ? YES : NO;
	
	DebugLog(@"Passphrase in cache? %@", passphraseInCache ? @"YES" : @"NO");
    
	return passphraseInCache;
}

#pragma mark - Proxies for OS X version differences.

- (id)dataSourceProxy {
    // 10.8 uses dataSource, 10.7 uses messageStore.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wselector"
    if([self respondsToSelector:@selector(dataSource)])
        return [self dataSource];
    if([self respondsToSelector:@selector(messageStore)])
       return [self messageStore];
#pragma clang diagnostic pop
    return nil;
}

- (void)MASetMessageInfo:(id)info subjectPrefixLength:(unsigned char)subjectPrefixLength to:(id)to sender:(id)sender type:(BOOL)type dateReceivedTimeIntervalSince1970:(double)receivedDate dateSentTimeIntervalSince1970:(double)sentDate messageIDHeaderDigest:(id)messageIDHeaderDigest inReplyToHeaderDigest:(id)headerDigest dateLastViewedTimeIntervalSince1970:(double)lastViewedDate {
	// Replace the GPGFlaggedString with an actual NSString, otherwise Drafts cannot be properly displayed
	// in some cases, since plist decoding doesn't work.
	NSString *newSender = sender;
	if([sender isKindOfClass:[GPGFlaggedString class]])
		newSender = [sender string];
	
	[self MASetMessageInfo:info subjectPrefixLength:subjectPrefixLength to:to sender:newSender type:type dateReceivedTimeIntervalSince1970:receivedDate dateSentTimeIntervalSince1970:sentDate messageIDHeaderDigest:messageIDHeaderDigest inReplyToHeaderDigest:headerDigest dateLastViewedTimeIntervalSince1970:lastViewedDate];
}

- (NSString *)gmDescription {
    
    return [NSString stringWithFormat:@"<%@: %p, library id:%lld conversationID:%lld\n\t",
//                                       "MIME encrypted: %@\n\t"
//                                       "MIME signed: %@\n\t"
//                                       "was decrypted successfully: %@\n\t"
//                                       "was verified successfully: %@\n\t"
//                                       "number of pgp attachments: %d\n\t"
//                                       "number of signatures: %d\n\t"
//                                       "pgp info collected: %@>",
                                        NSStringFromClass([self class]), self, (long long)[(id)self libraryID], (long long)[(id)self conversationID]
//                                            [[(id)self mailbox] displayName]
//            self.PGPEncrypted ? @"YES" : @"NO", self.PGPSigned ? @"YES" : @"NO",
//            self.PGPDecrypted ? @"YES" : @"NO", self.PGPVerified ? @"YES" : @"NO",
//            (unsigned int)[self.PGPAttachments count], (unsigned int)[self.PGPSignatures count],
//            self.PGPInfoCollected ? @"YES" : @"NO"
            ];
}

- (GMMessageSecurityFeatures *)securityFeatures {
    return [self getIvar:kMessageSecurityFeaturesKey];
}

//
//// TODO: Save all PGP info on the mimebody object instead.
- (id)MAParsedMessage {
    // This method is called, when a message is opened from outside the library (an .eml is loaded.)
    id messageData = [((MCMessage *)self) messageDataIncludingFromSpace:0x0 newDocumentID:0x0 fetchIfNotAvailable:0x1];
    id parsedMessage = nil;
    if (messageData) {
        MCMimePart *topLevelPart = [[MCMimePart alloc] initWithEncodedData:messageData];
        MCMimeBody *body = [MCMimeBody new];
        [body setIvar:kMimeBodyMessageKey value:self];
        [topLevelPart setIvar:@"MimeBody" value:body];
        [body setTopLevelPart:topLevelPart];
        [(MCMimePart *)topLevelPart parse];
        parsedMessage = [body parsedMessage];
    }
    return parsedMessage;
}

@end

#undef mailself



