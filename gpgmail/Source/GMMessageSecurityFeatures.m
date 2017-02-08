//
//  GMMessageSecurityParseResult.m
//  GPGMail
//
//  Created by Lukas Pitschl on 01.10.16.
//
//

#import "CCLog.h"

#import "NSObject+LPDynamicIvars.h"
#import "NSString+GPGMail.m"

#import "MCMessage.h"
#import "MimePart+GPGMail.h"
#import "Message+GPGMail.h"
#import "MCActivityMonitor.h"
#import "MimeBody+GPGMail.h"

#import "GMMessageSecurityFeatures.h"

@interface GMMessageSecurityFeatures (MimePartNotImplemented)

- (id)decryptedMimeBody;
    
@end

@interface GMMessageSecurityFeatures ()

- (void)collectSecurityFeaturesStartingWithMimePart:(GM_CAST_CLASS(MimePart *, id))topPart;

@end


@implementation GMMessageSecurityFeatures

- (id)init {
    return [super init];
}

+ (GMMessageSecurityFeatures *)securityFeaturesFromMimeBody:(id)mimeBody {
    GMMessageSecurityFeatures *securityFeatures = [self new];
    [securityFeatures collectSecurityFeaturesStartingWithMimePart:[mimeBody topLevelPart]];
    return securityFeatures;
}

- (void)setPGPEncrypted:(BOOL)isPGPEncrypted {
    [self setIvar:@"PGPEncrypted" value:@(isPGPEncrypted)];
}

- (BOOL)PGPEncrypted {
    NSNumber *isPGPEncrypted = [self getIvar:@"PGPEncrypted"];
    
    return [isPGPEncrypted boolValue];
}

- (BOOL)PGPSigned {
    NSNumber *isPGPSigned = [self getIvar:@"PGPSigned"];
    
    return [isPGPSigned boolValue];
}

- (void)setPGPSigned:(BOOL)isPGPSigned {
    [self setIvar:@"PGPSigned" value:@(isPGPSigned)];
}

- (BOOL)PGPPartlyEncrypted {
    NSNumber *isPGPEncrypted = [self getIvar:@"PGPPartlyEncrypted"];
    return [isPGPEncrypted boolValue];
}


- (void)setPGPPartlyEncrypted:(BOOL)isPGPEncrypted {
    [self setIvar:@"PGPPartlyEncrypted" value:@(isPGPEncrypted)];
}

- (BOOL)PGPPartlySigned {
    NSNumber *isPGPSigned = [self getIvar:@"PGPPartlySigned"];
    return [isPGPSigned boolValue];
}

- (void)setPGPPartlySigned:(BOOL)isPGPSigned {
    [self setIvar:@"PGPPartlySigned" value:@(isPGPSigned)];
}

- (NSUInteger)numberOfPGPAttachments {
    return [[self getIvar:@"PGPNumberOfPGPAttachments"] integerValue];
}

- (void)setNumberOfPGPAttachments:(NSUInteger)nr {
    [self setIvar:@"PGPNumberOfPGPAttachments" value:@((NSUInteger)nr)];
}

- (void)setPGPSignatures:(NSArray *)signatures {
    [self setIvar:@"PGPSignatures" value:signatures];
}

- (NSArray *)PGPSignatures {
    return [self getIvar:@"PGPSignatures"];
}

- (void)setPGPErrors:(NSArray *)errors {
    [self setIvar:@"PGPErrors" value:errors];
}

- (NSArray *)PGPErrors {
    return [self getIvar:@"PGPErrors"];
}

- (void)setPGPAttachments:(NSArray *)attachments {
    [self setIvar:@"PGPAttachments" value:attachments];
}

- (NSArray *)PGPAttachments {
    return [self getIvar:@"PGPAttachments"];
}

- (NSArray *)PGPSignatureLabels {
    // TODO: Re-implement this properly. might not even have to be on securityfeatures.
    NSString *senderEmail = @"";//[[self valueForKey:@"_sender"] gpgNormalizedEmail];
    
    // Check if the signature in the message signers is a GPGSignature, if
    // so, copy the email addresses and return them.
    NSMutableArray *signerLabels = [NSMutableArray array];
    NSArray *messageSigners = [self PGPSignatures];
    for(GPGSignature *signature in messageSigners) {
        // Check with the key manager if an updated key is available for
        // this signature, since auto-key-retrieve might have changed it.
        GPGKey *newKey = [[GPGMailBundle sharedInstance] keyForFingerprint:signature.fingerprint];
        signature.key = newKey.primaryKey;
        NSString *email = signature.email;
        if(email) {
            // If the sender E-Mail != signature E-Mail, we display the sender E-Mail if possible.
            if (![[email gpgNormalizedEmail] isEqualToString:senderEmail]) {
                GPGKey *key = signature.key;
                for (GPGUserID *userID in key.userIDs) {
                    if ([[userID.email gpgNormalizedEmail] isEqualToString:senderEmail]) {
                        email = userID.email;
                        break;
                    }
                }
            }
        } else {
            // Check if name is available and use that.
            if([signature.name length])
                email = signature.name;
            else
                // For some reason a signature might not have an email set.
                // This happens if the public key is not available (not downloaded or imported
                // from the signature server yet). In that case, display the user id.
                // Also, add an appropriate warning.
                email = [NSString stringWithFormat:@"0x%@", [signature.fingerprint shortKeyID]];
        }
        [signerLabels addObject:email];
    }
    
    return signerLabels;
}

- (BOOL)PGPInfoCollected {
    return [[self getIvar:@"PGPInfoCollected"] boolValue];
}

- (void)setPGPInfoCollected:(BOOL)infoCollected {
    [self setIvar:@"PGPInfoCollected" value:@(infoCollected)];
    // If infoCollected is set to NO, clear all associated info.
    if(!infoCollected)
        [self clearPGPInformation];
}

- (BOOL)PGPDecrypted {
    return [[self getIvar:@"PGPDecrypted"] boolValue];
}

- (void)setPGPDecrypted:(BOOL)isDecrypted {
    [self setIvar:@"PGPDecrypted" value:@(isDecrypted)];
}

- (BOOL)PGPVerified {
    return [[self getIvar:@"PGPVerified"] boolValue];
}

- (void)setPGPVerified:(BOOL)isVerified {
    [self setIvar:@"PGPVerified" value:@(isVerified)];
}

- (void)collectSecurityFeaturesStartingWithMimePart:(GM_CAST_CLASS(MimePart *, id))topPart {
    __block BOOL isEncrypted = NO;
    __block BOOL isSigned = NO;
    __block BOOL isPartlyEncrypted = NO;
    __block BOOL isPartlySigned = NO;
    NSMutableArray *errors = [NSMutableArray array];
    NSMutableArray *signatures = [NSMutableArray array];
    NSMutableArray *pgpAttachments = [NSMutableArray array];
    __block BOOL isDecrypted = NO;
    __block BOOL isVerified = NO;
    __block NSUInteger numberOfAttachments = 0;
    
    MCMimeBody *mimeBody = [topPart mimeBody];
    id decryptedBody = [topPart decryptedMimeBody];
    // If there's a decrypted message body, its top level part possibly holds information
    // about signatures and errors.
    // Theoretically it could contain encrypted inline data, signed inline data
    // and attachments, but for the time, that's out of scope.
    // This information is added to the message.
    //
    // If there's no decrypted message body, either the message contained
    // PGP inline data or failed to decrypt. In either case, the top part
    // passed in contains all the information.
    //MimePart *informationPart = decryptedBody == nil ? topPart : [decryptedBody topLevelPart];
    [topPart enumerateSubpartsWithBlock:^(GM_CAST_CLASS(MimePart *, id) currentPart) {
        // Only set the flags for non attachment parts to support
        // plain messages with encrypted/signed attachments.
        // Otherwise those would display as signed/encrypted as well.
        // application/pgp is a special case since Mail.app identifies it as an attachment, while its
        // truly a text/plain part (legacy pgp format)
        if([currentPart isAttachment] && ![currentPart isType:@"application" subtype:@"pgp"]) {
            if([currentPart PGPAttachment])
                [pgpAttachments addObject:currentPart];
        }
        else {
            isEncrypted |= [currentPart PGPEncrypted];
            isSigned |= [currentPart PGPSigned];
            isPartlySigned |= [currentPart PGPPartlySigned];
            isPartlyEncrypted |= [currentPart PGPPartlyEncrypted];
            if([currentPart PGPError])
                [errors addObject:[currentPart PGPError]];
            if([[currentPart PGPSignatures] count])
                [signatures addObjectsFromArray:[currentPart PGPSignatures]];
            isDecrypted |= [currentPart PGPDecrypted];
            // encrypted & signed & no error = verified.
            // not encrypted & signed & no error = verified.
            isVerified |= [currentPart PGPSigned];
        }
        
        // Count the number of attachments, but ignore signature.asc
        // and encrypted.asc files, since those are only PGP/MIME attachments
        // and not actual attachments.
        // We'll only see those attachments if the
        if([currentPart isAttachment]) {
            if([currentPart isPGPMimeEncryptedAttachment] || [currentPart isPGPMimeSignatureAttachment])
                return;
            else {
                numberOfAttachments++;
            }
        }
    }];
    
    // This is a normal message, out of here, otherwise
    // this might break a lot of stuff.
    if(!isSigned && !isEncrypted && ![pgpAttachments count] && ![errors count])
        return;
    
    if([pgpAttachments count]) {
        self.numberOfPGPAttachments = [pgpAttachments count];
        self.PGPAttachments = pgpAttachments;
    }
    // Set the flags based on the parsed message.
    // Happened before in decrypt bla bla bla, now happens before decodig is finished.
    // Should work better.
    GMMessageSecurityFeatures *decryptedMimeBodySecurityFeatures = [(MimeBody_GPGMail *)decryptedBody securityFeatures];
    
    Message *decryptedMessage = nil;
    if(decryptedBody)
        decryptedMessage = [decryptedBody message];
    
#warning Fix up. The decryptedMessage should be replaced by a GMMessageSecurityParseResult for the decrypted message.
    
    self.PGPEncrypted = isEncrypted || [decryptedMimeBodySecurityFeatures PGPEncrypted];
    self.PGPSigned = isSigned || [decryptedMimeBodySecurityFeatures PGPSigned];
    self.PGPPartlyEncrypted = isPartlyEncrypted || [decryptedMimeBodySecurityFeatures PGPPartlyEncrypted];
    self.PGPPartlySigned = isPartlySigned || [decryptedMimeBodySecurityFeatures PGPPartlySigned];
    [signatures addObjectsFromArray:[decryptedMimeBodySecurityFeatures PGPSignatures]];
    self.PGPSignatures = signatures;
    [errors addObjectsFromArray:[decryptedMimeBodySecurityFeatures PGPErrors]];
    self.PGPErrors = errors;
    [pgpAttachments addObjectsFromArray:[decryptedMimeBodySecurityFeatures PGPAttachments]];
    self.PGPDecrypted = isDecrypted;
    self.PGPVerified = isVerified;
    
    // TODO: If still necessary, this must be done in Message or MimeBody.
    //[self fakeMessageFlagsIsEncrypted:self.PGPEncrypted isSigned:self.PGPSigned];
//    if(decryptedMessage) {
//        [(Message_GPGMail *)decryptedMessage fakeMessageFlagsIsEncrypted:self.PGPEncrypted isSigned:self.PGPSigned];
//    }
    //    // The problem is, Mail.app would correctly apply the rules, if we didn't
//    // deactivate the snippet generation. But since we do, because it's kind of
//    // a pain in the ass, it doesn't.
//    // So we re-evaluate the message rules here and then they should be applied correctly.
//    // ATTENTION: We have to make sure that the user actively selected this message,
//    //			  otherwise, the body data is not yet available, and will 'cause the evaluation rules
//    //			  to wreak havoc.
//    if(!self.isSMIMEEncrypted && !self.isSMIMESigned)
//        [self applyMatchingRulesIfNecessary];
    
    // Only for test purpose, after the correct error to be displayed should be constructed.
    GM_CAST_CLASS(MFError *, id) error = nil;
    if([errors count])
        error = errors[0];
    else if([self.PGPAttachments count])
        error = [self errorSummaryForPGPAttachments:self.PGPAttachments];
    
    // Set the error on the activity monitor so the error banner is displayed
    // on above the message content.
    if(error) {
        [(MCActivityMonitor *)[GM_MAIL_CLASS(@"ActivityMonitor") currentMonitor] setError:error];
        // On Mavericks the ActivityMonitor trick doesn't seem to work, since the currentMonitor
        // doesn't necessarily have to belong to the current message.
        // So we store the mainError on the message and it's later used by the CertificateBannerController thingy.
        [self setIvar:@"PGPMainError" value:error];
    }
    else {
        if([self getIvar:@"PGPMainError"]) {
            [self removeIvar:@"PGPMainError"];
        }
    }
    
    DebugLog(@"%@ Decrypted Message [%@]:\n\tisEncrypted: %@, isSigned: %@,\n\tisPartlyEncrypted: %@, isPartlySigned: %@\n\tsignatures: %@\n\terrors: %@",
             [decryptedBody message], [(MCMessage *)[decryptedBody message] subject], [decryptedMimeBodySecurityFeatures PGPEncrypted] ? @"YES" : @"NO", [decryptedMimeBodySecurityFeatures PGPSigned] ? @"YES" : @"NO",
             [decryptedMimeBodySecurityFeatures PGPPartlyEncrypted] ? @"YES" : @"NO", [decryptedMimeBodySecurityFeatures PGPPartlySigned] ? @"YES" : @"NO", [decryptedMimeBodySecurityFeatures PGPSignatures], [decryptedMimeBodySecurityFeatures PGPErrors]);
    
    DebugLog(@"%@ Message [%@]:\n\tisEncrypted: %@, isSigned: %@,\n\tisPartlyEncrypted: %@, isPartlySigned: %@\n\tsignatures: %@\n\terrors: %@\n\tattachments: %@",
             [(MimeBody_GPGMail *)mimeBody message], [[(MimeBody_GPGMail *)mimeBody message] subject], self.PGPEncrypted ? @"YES" : @"NO", self.PGPSigned ? @"YES" : @"NO",
             self.PGPPartlyEncrypted ? @"YES" : @"NO", self.PGPPartlySigned ? @"YES" : @"NO", self.PGPSignatures, self.PGPErrors, self.PGPAttachments);
    
    // Fix the number of attachments, this time for real!
    // Uncomment once completely implemented.
    // TODO: If this is still necessary, move this to mimeBody or message.
//    [[self dataSourceProxy] setNumberOfAttachments:(unsigned int)numberOfAttachments isSigned:self.isSigned isEncrypted:self.isEncrypted forMessage:self];
//    if(decryptedMessage)
//        [[(Message_GPGMail *)decryptedMessage dataSourceProxy] setNumberOfAttachments:(unsigned int)numberOfAttachments isSigned:self.isSigned isEncrypted:self.isEncrypted forMessage:decryptedMessage];
//    // Set PGP Info collected so this information is not overwritten.
//    self.PGPInfoCollected = YES;
}

- (NSError *)errorSummaryForPGPAttachments:(NSArray *)attachments {
    NSUInteger verificationErrors = 0;
    NSUInteger decryptionErrors = 0;
    
    for(GM_CAST_CLASS(MimePart *, id) part in attachments) {
        if(![part PGPError])
            continue;
        
        if([[(NSError *)[part PGPError] userInfo] valueForKey:@"VerificationError"])
            verificationErrors++;
        else if([[(NSError *)[part PGPError] userInfo] valueForKey:@"DecryptionError"])
            decryptionErrors++;
    }
    
    if(!verificationErrors && !decryptionErrors)
        return nil;
    
    NSUInteger totalErrors = verificationErrors + decryptionErrors;
    
    NSString *title = nil;
    NSString *message = nil;
    // 1035 says decryption error, 1036 says verification error.
    // If both, use 1035.
    NSUInteger errorCode = 0;
    
    if(verificationErrors && decryptionErrors) {
        // @"%d Anhänge konnten nicht entschlüsselt oder verifiziert werden."
        title = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENTS_DECRYPT_VERIFY_ERROR_TITLE");
        message = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENTS_DECRYPT_VERIFY_ERROR_MESSAGE");
        errorCode = 1035;
    }
    else if(verificationErrors) {
        if(verificationErrors == 1) {
            title = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENT_VERIFY_ERROR_TITLE");
            message = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENT_VERIFY_ERROR_MESSAGE");
        }
        else {
            title = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENTS_VERIFY_ERROR_TITLE");
            message = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENTS_VERIFY_ERROR_MESSAGE");
        }
        errorCode = 1036;
    }
    else if(decryptionErrors) {
        if(decryptionErrors == 1) {
            title = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENT_DECRYPT_ERROR_TITLE");
            message = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENT_DECRYPT_ERROR_MESSAGE");
        }
        else {
            title = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENTS_DECRYPT_ERROR_TITLE");
            message = GMLocalizedString(@"MESSAGE_BANNER_PGP_ATTACHMENTS_DECRYPT_ERROR_MESSAGE");
        }
        errorCode = 1035;
    }
    
    title = [NSString stringWithFormat:title, totalErrors];
    
    // TODO: This works differently
    GM_CAST_CLASS(MFError *, id) error = nil;
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    
    [userInfo setValue:title forKey:@"_MFShortDescription"];
    [userInfo setValue:message forKey:@"NSLocalizedDescription"];
    [userInfo setValue:@YES forKey:@"DecryptionError"];
    
    error = [GPGMailBundle errorWithCode:errorCode userInfo:userInfo];
    
    return error;
}

- (void)clearPGPInformation {
    self.PGPSignatures = nil;
    self.PGPEncrypted = NO;
    self.PGPPartlyEncrypted = NO;
    self.PGPSigned = NO;
    self.PGPPartlySigned = NO;
    self.PGPDecrypted = NO;
    self.PGPVerified = NO;
    self.PGPErrors = nil;
    self.PGPAttachments = nil;
    self.numberOfPGPAttachments = 0;
}


@end
