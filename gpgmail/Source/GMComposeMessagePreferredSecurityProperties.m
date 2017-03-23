//
//  GMComposeMessagePreferredSecurityProperties.m
//  GPGMail
//
//  Created by Lukas Pitschl on 22.11.16.
//
//

#import "GMComposeMessagePreferredSecurityProperties.h"

#import "CCLog.h"
#import "NSString+GPGMail.h"

//#import "GPGKey.h"

#import "GPGMailBundle.h"

#import "MCKeychainManager.h"
#import "MCMessage.h"
#import "ComposeBackEnd.h"

#import "ComposeBackEnd+GPGMail.h"
#import "GMSecurityHistory.h"

@interface GMComposeMessagePreferredSecurityProperties ()

@property (nonatomic, readwrite, retain) MCMessage *message;

@property (nonatomic, readwrite, copy) NSDictionary *SMIMESigningIdentities;
@property (nonatomic, readwrite, copy) NSDictionary *SMIMEEncryptionCertificates;

@property (nonatomic, readwrite, copy) NSDictionary *PGPSigningKeys;
@property (nonatomic, readwrite, copy) NSDictionary *PGPEncryptionKeys;

@property (nonatomic, readwrite, assign) BOOL shouldSignMessage;
@property (nonatomic, readwrite, assign) BOOL shouldEncryptMessage;

@end

@implementation GMComposeMessagePreferredSecurityProperties

- (id)initWithSender:(NSString *)sender recipients:(NSArray *)recipients {
    if((self = [super init])) {
        _sender = [sender copy];
        _recipients = [recipients copy];
        _cachedSigningIdentities = [[NSMutableDictionary alloc] init];
        _cachedEncryptionCertificates = [[NSMutableDictionary alloc] init];
        _messageIsDraft = NO;
        _messageIsReply = NO;
        _messageIsFowarded = NO;
        _userDidChooseSecurityMethod = NO;
        
        _userShouldSignMessage = ThreeStateBooleanUndetermined;
        _userShouldEncryptMessage = ThreeStateBooleanUndetermined;
    }
    
    return self;
}

- (id)initWithSender:(NSString *)sender recipients:(NSArray *)recipients userShouldSignMessage:(ThreeStateBoolean)userShouldSign userShouldEncryptMessage:(ThreeStateBoolean)userShouldEncrypt {
    if((self = [self initWithSender:sender recipients:recipients])) {
        _userShouldSignMessage = userShouldSign;
        _userShouldEncryptMessage = userShouldEncrypt;
    }
    
    return self;
}

+ (GPGMAIL_SECURITY_METHOD)defaultSecurityMethod {
    return [GMSecurityHistory defaultSecurityMethod];
}

// Comment later. But for debugging it's nice!
- (void)setUserShouldSignMessage:(ThreeStateBoolean)userShouldSignMessage {
    // Since our three state boolean enum defines False as 0 and True as 1, it should be save
    // to use the bool as is. No need to convert it to ThreeStateBooleanTrue or ThreeStateBooleanFalse
    _userShouldSignMessage = userShouldSignMessage;
}

- (void)setUserShouldEncryptMessage:(ThreeStateBoolean)userShouldEncryptMessage {
    _userShouldEncryptMessage = userShouldEncryptMessage;
}

- (BOOL)shouldSignMessage {
    if(!_canSign)
        return NO;
    
    if(_userShouldSignMessage != ThreeStateBooleanUndetermined)
        return _userShouldSignMessage;
    
    return _shouldSignMessage;
}

- (BOOL)shouldEncryptMessage {
    if(!_canEncrypt)
        return NO;
    
    if(_userShouldEncryptMessage != ThreeStateBooleanUndetermined)
        return _userShouldEncryptMessage;
    
    return _shouldEncryptMessage;
}

- (void)setSecurityMethod:(GPGMAIL_SECURITY_METHOD)securityMethod {
    _securityMethod = securityMethod;
    _userDidChooseSecurityMethod = YES;
}

- (void)addHintsFromBackEnd:(ComposeBackEnd *)backEnd {
    _messageIsReply = [(ComposeBackEnd_GPGMail *)backEnd messageIsBeingReplied];
    _messageIsDraft = [(ComposeBackEnd_GPGMail *)backEnd draftIsContinued];
    _messageIsFowarded = [(ComposeBackEnd_GPGMail *)backEnd messageIsBeingForwarded];
    
    self.message = [backEnd originalMessage];
}

- (GPGKey *)encryptionKeyForDraft {
    // Check if a key for encrypting the draft is available matching the sender.
    // Otherwise, return any key pair with encryption capabilities.
    NSString *senderAddress = [self.sender gpgNormalizedEmail];
    id key = [self.PGPSigningKeys valueForKey:senderAddress];
    if([key isKindOfClass:[GPGKey class]] && ((GPGKey *)key).canAnyEncrypt) {
        return key;
    }
    return [[GPGMailBundle sharedInstance] anyPersonalPublicKeyWithPreferenceAddress:senderAddress];
}

- (void)computePreferredSecurityPropertiesForSecurityMethod:(GPGMAIL_SECURITY_METHOD)securityMethod {
    // Load signing identity and certificates for S/MIME.
    NSMutableDictionary *signingIdentities = [self.cachedSigningIdentities mutableCopy];
    NSMutableDictionary *encryptionCertificates = [self.cachedEncryptionCertificates mutableCopy];
    
    // While it might seem counter intuitive, the default for encrypt is set to yes if recipients are available.
    // This makes sense, since the first recipient with no certificate available will set the status to NO.
    // Other cases don't change the default value.
    BOOL canSMIMESign = NO;
    BOOL canSMIMEEncrypt = [self.recipients count] ? YES : NO;
    BOOL canPGPSign = NO;
    BOOL canPGPEncrypt = [self.recipients count] ? YES : NO;
    
    NSString *sender = [self.sender copy];
    NSArray *recipients = [self.recipients copy];
    
    if(sender) {
        // Only accept cached S/MIME signing identities, otherwise run a new check.
        id signingIdentity = signingIdentities[sender];
        if(signingIdentity && ([signingIdentity isKindOfClass:[GPGKey class]] || signingIdentity == [NSNull null])) {
            signingIdentity = nil;
        }
        if(!signingIdentity) {
            signingIdentity = (__bridge id)[MCKeychainManager copySigningIdentityForAddress:sender];
            signingIdentities[sender] = signingIdentity ? signingIdentity : [NSNull null];
        }
        canSMIMESign = signingIdentities[sender] && signingIdentities[sender] != [NSNull null] ? YES : NO;
    }
    else {
        canSMIMESign = NO;
    }
    
    //BOOL canEncrypt = [recipients count] ? YES : NO;
    for(id recipient in recipients) {
        // Only accept cached S/MIME encryption certificates, otherwise for a new check.
        id certificate = encryptionCertificates[recipient];
        if(certificate && ([certificate isKindOfClass:[GPGKey class]] || certificate == [NSNull null])) {
            certificate = nil;
        }
        if(!certificate) {
            certificate = [MCKeychainManager copyEncryptionCertificateForAddress:recipient];
            encryptionCertificates[recipient] = certificate ? certificate : [NSNull null];
        }
        if(encryptionCertificates[recipient] == [NSNull null]) {
            canSMIMEEncrypt = NO;
        }
    }
    
    // Load signing key and encryption keys for OpenPGP.
    NSMutableDictionary *signingKeys = [self.cachedSigningIdentities mutableCopy];
    NSMutableDictionary *encryptionKeys = [self.cachedEncryptionCertificates mutableCopy];
    
    // S/MIME treats the sender in a case sensitive manner, PGP does not.
    NSString *senderAddress = [sender gpgNormalizedEmail];
    
    // Only accept cached PGP signing keys, otherwise run a new check.
    id signingKey = signingKeys[senderAddress];
    if(sender) {
        if(signingKey && (![signingKey isKindOfClass:[GPGKey class]] || signingKey == [NSNull null])) {
            signingKey = nil;
        }
        if(!signingKey) {
            NSArray *signingKeyList = [[[GPGMailBundle sharedInstance] signingKeyListForAddress:senderAddress] allObjects];
            // TODO: Consider pereferring the default key if one is configured.
            signingKeys[senderAddress] = [signingKeyList count] > 0 ? signingKeyList[0] : [NSNull null];
            // In order to trick mail into accepting the key, it has to be added under the sender
            // with email and full name as well. Otherwise, the last check before calling
            // -[ComposeBackEnd _makeMessageWithContents:isDraft:shouldSign:shouldEncrypt:shouldSkipSignature:shouldBePlainText:]
            // will disable signing, since no key for the full address can be found in the _signingIdentities dictionary.
            signingKeys[sender] = signingKeys[senderAddress];
        }
        canPGPSign = signingKeys[senderAddress] && signingKeys[senderAddress] != [NSNull null] ? YES : NO;
    }
    else {
        canPGPSign = NO;
    }
    
    //BOOL canEncrypt = [recipients count] ? YES : NO;
    for(id recipient in recipients) {
        NSString *normalizedRecipient = [recipient gpgNormalizedEmail];
        // Only accept cached PGP encryption certificates, otherwise for a new check.
        id key = encryptionKeys[normalizedRecipient];
        if(key && (![key isKindOfClass:[GPGKey class]] || key == [NSNull null])) {
            key = nil;
        }
        if(!key) {
            NSArray *keyList = [[[GPGMailBundle sharedInstance] publicKeyListForAddresses:@[normalizedRecipient]] allObjects];
            encryptionKeys[normalizedRecipient] = [keyList count] > 0 ? keyList[0] : [NSNull null];
        }
        if(encryptionKeys[normalizedRecipient] == [NSNull null]) {
            canPGPEncrypt = NO;
        }
    }
    
    // Now we know, if signing and encryption is available. Now on to determine, what security properties should be enabled.
    GPGMAIL_SIGN_FLAG signFlags = 0;
    if(canPGPSign)
        signFlags |= GPGMAIL_SIGN_FLAG_OPENPGP;
    if(canSMIMESign)
        signFlags |= GPGMAIL_SIGN_FLAG_SMIME;
    
    GPGMAIL_ENCRYPT_FLAG encryptFlags = 0;
    if(canPGPEncrypt)
        encryptFlags |= GPGMAIL_ENCRYPT_FLAG_OPENPGP;
    if(canSMIMEEncrypt)
        encryptFlags |= GPGMAIL_ENCRYPT_FLAG_SMIME;
    
    GMSecurityHistory *securityHistory = [[GMSecurityHistory alloc] init];
    GMSecurityOptions *securityOptions = nil;
    
    BOOL canEncrypt = NO;
    BOOL canSign = NO;
    
    if(securityMethod == GPGMAIL_SECURITY_METHOD_UNDETERMINDED) {
        if(_messageIsReply || _messageIsFowarded) {
            MCMessage *originalMessage = self.message;
            securityOptions = [securityHistory bestSecurityOptionsForReplyToMessage:originalMessage signFlags:signFlags encryptFlags:encryptFlags];
        }
        else if(_messageIsDraft) {
            MCMessage *originalMessage = self.message;
            securityOptions = [securityHistory bestSecurityOptionsForMessageDraft:originalMessage signFlags:signFlags encryptFlags:encryptFlags];
        }
        else {
            securityOptions = [securityHistory bestSecurityOptionsForSender:sender recipients:recipients signFlags:signFlags encryptFlags:encryptFlags];
        }
        securityMethod = securityOptions.securityMethod;
        
        if(securityMethod == GPGMAIL_SECURITY_METHOD_OPENPGP) {
            canEncrypt = canPGPEncrypt;
            canSign = canPGPSign;
        }
        else {
            canEncrypt = canSMIMEEncrypt;
            canSign = canSMIMESign;
        }
        if(securityMethod == GPGMAIL_SECURITY_METHOD_OPENPGP) {
            DebugLog(@"Security Method is OpenPGP");
            DebugLog(@"Can OpenPGP Encrypt: %@", canPGPEncrypt ? @"YES" : @"NO");
            DebugLog(@"Can OpenPGP Sign: %@", canPGPSign ? @"YES" : @"NO");
        }
        else if(securityMethod == GPGMAIL_SECURITY_METHOD_SMIME) {
            DebugLog(@"Security Method is S/MIME");
            DebugLog(@"Can S/MIME Encrypt: %@", canSMIMEEncrypt ? @"YES" : @"NO");
            DebugLog(@"Can S/MIME Sign: %@", canSMIMESign ? @"YES" : @"NO");
        }
    }
    else {
        canEncrypt = securityMethod == GPGMAIL_SECURITY_METHOD_OPENPGP ? canPGPEncrypt : canSMIMEEncrypt;
        canSign = securityMethod == GPGMAIL_SECURITY_METHOD_OPENPGP ? canPGPSign : canSMIMESign;
        if(_messageIsReply || _messageIsFowarded) {
            MCMessage *originalMessage = self.message;
            securityOptions = [securityHistory bestSecurityOptionsForReplyToMessage:originalMessage signFlags:signFlags encryptFlags:encryptFlags];
        }
        else if(_messageIsDraft) {
            MCMessage *originalMessage = self.message;
            securityOptions = [securityHistory bestSecurityOptionsForMessageDraft:originalMessage signFlags:signFlags encryptFlags:encryptFlags];
        }
        else {
            securityOptions = [securityHistory bestSecurityOptionsForSender:sender recipients:recipients securityMethod:securityMethod canSign:canSign canEncrypt:canEncrypt];
        }
    }
    
    // DON'T use self.securityMethod. The property is only supposed to be used from outside, since
    // it also sets the userDidChooseSecurityMethod value.
    _securityMethod = securityMethod;
    
    _shouldSignMessage = securityOptions.shouldSign;
    _shouldEncryptMessage = securityOptions.shouldEncrypt;
    
    _canSMIMESign = canSMIMESign;
    _canSMIMEEncrypt = canSMIMEEncrypt;
    _canPGPSign = canPGPSign;
    _canPGPEncrypt = canPGPEncrypt;
    
    _canSign = canSign;
    _canEncrypt = canEncrypt;
    
    self.SMIMESigningIdentities = signingIdentities;
    self.SMIMEEncryptionCertificates = encryptionCertificates;
    self.PGPSigningKeys = signingKeys;
    self.PGPEncryptionKeys = encryptionKeys;
    
    if(securityMethod == GPGMAIL_SECURITY_METHOD_SMIME) {
        self.cachedSigningIdentities = _SMIMESigningIdentities;
        self.cachedEncryptionCertificates = _SMIMEEncryptionCertificates;
    }
    else {
        self.cachedSigningIdentities = _PGPSigningKeys;
        self.cachedEncryptionCertificates = _PGPEncryptionKeys;
    }
}

@end
