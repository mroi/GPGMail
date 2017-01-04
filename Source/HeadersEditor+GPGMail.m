/* HeadersEditor+GPGMail.m re-created by Lukas Pitschl (@lukele) on Wed 25-Aug-2011 */

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

#import <Libmacgpg/Libmacgpg.h>
#import <NSObject+LPDynamicIvars.h>
#import "CCLog.h"
#import "MFMailAccount.h"
//#import "AddressAttachment.h"
//#import <MailDocumentEditor.h>
//#import "MailNotificationCenter.h"
#import "Message+GPGMail.h"
#import "MailDocumentEditor+GPGMail.h"
#import "HeadersEditor.h"
//#import "ComposeHeaderView.h"
#import "HeadersEditor+GPGMail.h"
#import "ComposeBackEnd.h"
#import "ComposeBackEnd+GPGMail.h"
#import "GPGMailBundle.h"
#import "NSString+GPGMail.h"
#import "GMSecurityControl.h"
#import "NSObject+LPDynamicIvars.h"
//#import <NSString-EmailAddressString.h>
#import "GMComposeKeyEventHandler.h"
//#import "OptionalView.h"
#import "GMSecurityHistory.h"
#import "MUITokenAddress.h"
#import "MUIAddressTokenAttachmentCell.h"
#import "ComposeViewController.h"
#import "MailApp.h"

#import "GMComposeMessagePreferredSecurityProperties.h"

#define mailself ((HeadersEditor *)self)

@interface HeadersEditor_GPGMail (NoImplementation)
- (void)changeFromHeader:(NSPopUpButton *)sender;
@end

const NSString *kHeadersEditorFromControlGPGKeyKey = @"HeadersEditorFromControlGPGKey";
const NSString *kHeadersEditorFromControlParentItemKey = @"HeadersEditorFromControlParentItem";

@implementation HeadersEditor_GPGMail

- (void)MAAwakeFromNib {
    [self MAAwakeFromNib];
	
    [(NSNotificationCenter *)[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyringUpdated:) name:GPGMailKeyringUpdatedNotification object:nil];
		
	// VoiceOver uses the accessibilityDescription of NSImage for the encrypt and sign buttons, if there is no other text for accessibility.
	// The lock-images have a default of "lock" and "unlocked lock". (NSLockLockedTemplate and NSLockUnlockedTemplate)
	NSImage *signOnImage = [NSImage imageNamed:@"SignatureOnTemplate"];
	if (signOnImage) {
		[signOnImage setAccessibilityDescription:[GPGMailBundle localizedStringForKey:@"ACCESSIBILITY_SIGN_ON_IMAGE"]];
	}
	NSImage *signOffImage = [NSImage imageNamed:@"SignatureOffTemplate"];
	if (signOffImage) {
		[signOffImage setAccessibilityDescription:[GPGMailBundle localizedStringForKey:@"ACCESSIBILITY_SIGN_OFF_IMAGE"]];
	}
	
//	GMSecurityControl *signControl = [[GMSecurityControl alloc] initWithControl:[self valueForKey:@"_signButton"] tag:SECURITY_BUTTON_SIGN_TAG];
//    [self setValue:signControl forKey:@"_signButton"];
//    
//    GMSecurityControl *encryptControl = [[GMSecurityControl alloc] initWithControl:[self valueForKey:@"_encryptButton"] tag:SECURITY_BUTTON_ENCRYPT_TAG];
//    [self setValue:encryptControl forKey:@"_encryptButton"];
//	
//    // Configure setting the tool tip by unbinding the controls toolTip.
//    // We will update it, after _updateSecurityStateInBackground is run.
//    if([GPGMailBundle isYosemite]) {
//        [signControl unbind:@"toolTip"];
//        [encryptControl unbind:@"toolTip"];
//    }
//
    NSView *optionalView = (NSView *)[[self valueForKey:@"_signButton"] superview];
	GMComposeKeyEventHandler *handler = [[GMComposeKeyEventHandler alloc] initWithView:optionalView];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wselector"
	handler.eventsAndSelectors = [NSArray arrayWithObjects:
		@{@"keyEquivalent": @"y", @"keyEquivalentModifierMask": @(NSCommandKeyMask | NSAlternateKeyMask), @"target": [mailself signButton], @"selector": [NSValue valueWithPointer:@selector(performClick:)]},
		@{@"keyEquivalent": @"x", @"keyEquivalentModifierMask": @(NSCommandKeyMask | NSAlternateKeyMask), @"target": [mailself encryptButton], @"selector": [NSValue valueWithPointer:@selector(performClick:)]},
	nil];
#pragma clang diagnostic pop

	
}

// TODO: Remove - better implementation later in this file.
//- (void)MASecurityControlChanged:(id)securityControl {
//    GMSecurityControl *signControl = [self valueForKey:@"_signButton"];
//    GMSecurityControl *encryptControl = [self valueForKey:@"_encryptButton"];
//    NSSegmentedControl *originalSecurityControl = securityControl;
//	
//	    
//    securityControl = signControl.control == securityControl ? signControl : encryptControl;
//    // The securityControl passed to this method is an NSSegmentControl.
//	// So the only chance to find out what the new status of the control is,
//	// is to check its current image. (I really thought I was crazy writing this code,
//	// now it all makes sense again. WHAT A RELIEF)
//	// It's possible this is not necessary on
//    //if(![GPGMailBundle isYosemite])
//        [securityControl updateStatusFromImage:[originalSecurityControl imageForSegment:0]];
//    
//    [self MASecurityControlChanged:securityControl];
//}

- (void)MA_updateFromControl {
    // _updateFromAndSignatureControls: was renamed to to updateFromControl on Yosemite.
    // Unfortunately updateFromControl doesn't take any arguments, which means,
    // that we have to define a new method to hook into it.
    // This method has to be run on the mainthread.
    if(![NSThread mainThread])
        [self performSelectorOnMainThread:@selector(_updateFromControl) withObject:nil waitUntilDone:NO];
    
    [self MA_updateFromControl];
    [self setupFromControlCrossVersion];
}

- (void)setupFromControlCrossVersion {
    // Adjusted to work on Yosemite as well.
    
    // Thanks to Hopper (YES, it's fantastic) it's now clear that
    // _updateFromAndSignatureControls calls setAccountFieldEnabled|Visible
    // and configureAccountPopUpSize on the ComposeHeaderView.
    
    // If there's only one account setup, Mail.app chooses to not to display
    // the "From:" field. That's alright, unless there are multiple secret keys
    // available for the same account. In such a case, GPGMail will fill the
    // popup and force it to be displayed, so that the user can choose which
    // secret key to use.
    NSPopUpButton *fromPopup = [self fromPopup];
    if([[fromPopup itemArray] count] == 1 &&
       ![[[fromPopup itemArray] objectAtIndex:0] attributedTitle]) {
        [self fixEmptyAccountPopUpIfNecessary];
    }
    else {
        [(HeadersEditor *)self _setVisibilityForFromView:YES];
    }
    
    // If any luck, the security option should be known by now.
    // It's not, but it still works as assumed.
    ComposeBackEnd *backEnd = [GPGMailBundle backEndFromObject:self];
    // Make sure that default method is considered, if none is set.
    
    GPGMAIL_SECURITY_METHOD currentSecurityMethod = !((ComposeBackEnd_GPGMail *)backEnd).preferredSecurityProperties ? [GMComposeMessagePreferredSecurityProperties defaultSecurityMethod] : ((ComposeBackEnd_GPGMail *)backEnd).preferredSecurityProperties.securityMethod;
    BOOL addSecretKeys = currentSecurityMethod == GPGMAIL_SECURITY_METHOD_OPENPGP;
    [self updateFromAndAddSecretKeysIfNecessary:@(addSecretKeys)];
}

- (void)fixEmptyAccountPopUpIfNecessary {
    // 1. Find the accounts to be displayed.
    // TODO: Find out what replaces this in sierra
    NSArray *accounts = (NSArray *)[MFMailAccount allEmailAddressesIncludingDisplayName:YES];
    // There should only be on account available, otherwise we wouldn't be here.
	NSString *onlyAccount = [[accounts objectAtIndex:0] gpgNormalizedEmail];
	BOOL multipleKeysAvailable = [[[GPGMailBundle sharedInstance] signingKeyListForAddress:onlyAccount] count] > 1;
	
	if(!multipleKeysAvailable)
		return;
	
	Class AddressAttachmentClass = NSClassFromString(@"MUIAddressTokenAttachmentCell");
	
    NSPopUpButton *fromPopup = [self fromPopup];
    // 3. Construct the style of the menu.
    NSFont *font = [NSFont menuFontOfSize:[[(NSPopUpButtonCell *)[fromPopup cell] font] pointSize]];
    NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
    [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *externalAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
										[AddressAttachmentClass colorForExternalDomain], NSForegroundColorAttributeName,
                                        font, NSFontAttributeName, nil];
    NSDictionary *normalAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:font, NSFontAttributeName,
									  paragraphStyle, NSParagraphStyleAttributeName, nil];
    [fromPopup removeAllItems];
    [fromPopup addItemsWithTitles:accounts];
    if([accounts count]) {
        NSUInteger i = 0;
        for(id account in accounts) {
            NSDictionary *attributes = normalAttributes;
            if([AddressAttachmentClass addressIsExternal:account])
                attributes = externalAttributes;
            NSAttributedString *title = [[NSAttributedString alloc] initWithString:account attributes:attributes];
            [[fromPopup itemAtIndex:i] setAttributedTitle:title];
			[[fromPopup itemAtIndex:i] setRepresentedObject:account];
            i++;
        }
    }
    
    // Set the field visible so the layout will be adjusted accordingly.
    if(multipleKeysAvailable) {
        [self _setVisibilityForFromView:YES];
	}
}

- (void)MAUpdateSecurityControls {
	// New Sierra way to do this.
    ComposeBackEnd *backEnd = [[mailself composeViewController] backEnd];
    
    // Implementation of the block <arg1> passed to updateSMIMEStatus:
    // TODO: As Apple does, we should move this code to -[HeadersEditor _updateSecurityControls]
    // and pass it into updateSMIMEStatus. Choose the version that is more readable/easier to update.
    [backEnd updateSMIMEStatus:^{
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            BOOL canSign = [backEnd canSign];
            // Apple only sets canEncrypt if canSign is YES, since S/MIME requires a valid signature certificate
            // in order to perform encryptions. In OpenPGP we allow encryption, even if no key to sign a message
            // is available, so canEncrypt will also be set.
            BOOL canEncrypt = [backEnd canEncrypt];
            
            // Apple only shows the buttons to toggle sign and encrypt if signing is possible.
            // OpenPGP does work if only sign or encrypt is available, so we'll also show the buttons
            // if sign is not is possible, but only encrypt.
            [mailself _setVisibilityForEncryptionAndSigning:canSign || canEncrypt];
            [mailself setCanSign:canSign];
            [mailself setCanEncrypt:canEncrypt];
            
            // For reference, the original Apple code follows below.
            // Apple uses standard defaults to remember the last set status of sign and encrypt.
            // GPGMail however determines this status based on user preference.
            //
            // Apple Code:
            // MailApp *app = [[GPGMailBundle resolveMailClassFromName:@"MailApp"] sharedApplication];
            // BOOL signIfPossible = canSign ? [app signOutgoingMessages] : NO;
            // BOOL encryptIfPossible = canEncrypt ? [app encryptOutgoingMessages] : NO;
            //
            // GPGMail Code:
            GMComposeMessagePreferredSecurityProperties *preferredSecurityProperties = [(ComposeBackEnd_GPGMail *)backEnd preferredSecurityProperties];
            BOOL signIfPossible = preferredSecurityProperties.shouldSignMessage;
            BOOL encryptIfPossible = preferredSecurityProperties.shouldEncryptMessage;
            
            [mailself setMessageIsToBeSigned:signIfPossible];
            [backEnd setSignIfPossible:signIfPossible];
            [mailself setMessageIsToBeEncrypted:encryptIfPossible];
            [backEnd setEncryptIfPossible:encryptIfPossible];
            // Currently a no-op in Mail, for whatever reason.
            [[mailself composeViewController] encryptionStatusDidChange];
            // Last but not least, update the security accessory view.
            [(MailDocumentEditor_GPGMail *)[mailself composeViewController] updateSecurityMethodAccessoryView];
        }];
    }];
    
    return;
    
    // Old way we did it by calling Mail's implementation.
    
    // Do nothing, if documentEditor is no longer set.
	// Might already have been released, or some such...
	// Belongs to: #624.
    // MailApp seems to call S in Yosemite to cancel previous updates.
    // That's highly interesting!.
	// DocumentEditor no longer exists in El Capitan. Seems to have been replaced by ComposeViewController.
	if([GPGMailBundle isElCapitan]) {
		if([self respondsToSelector:@selector(composeViewController)] && ![self composeViewController])
			return;
	}
	else {
		if(![self valueForKey:@"_documentEditor"])
			return;
	}
	
	[self MAUpdateSecurityControls];
}

- (void)MA_updateSecurityStateInBackgroundForRecipients:(NSArray *)recipients sender:(id)sender {
    [self MA_updateSecurityStateInBackgroundForRecipients:recipients sender:sender];
	
	// Do the same as _updateSecurityStateInBackgroundForRecipients and update the
	// symmetric UI part on the main thread.
	typeof(self) __weak weakSelf = self;
	
	[[NSOperationQueue mainQueue] addOperationWithBlock:^{
		typeof(weakSelf) __strong strongSelf = weakSelf;
		if(!strongSelf)
			return;
        
        // Update tool tips.
        [strongSelf updateEncryptAndSignButtonToolTips];
		[strongSelf updateSymmetricButton];
	}];
}

- (void)MASetCanSign:(BOOL)canSign {
    // On Yosemite the button state of the sign button is bound to
    // this canSign property. Since canSignFromAddress always returns true in GPGMail,
    // because otherwise, canEncrypt would not always be evaluated, we have
    // to set the real value here, which is contained in SignIsPossible.
    ComposeBackEnd *backEnd = [GPGMailBundle backEndFromObject:self];
    NSDictionary *securityProperties = ((ComposeBackEnd_GPGMail *)backEnd).securityProperties;
    if(securityProperties[@"SignIsPossible"])
        canSign = [securityProperties[@"SignIsPossible"] boolValue];
    [self MASetCanSign:canSign];
}

- (void)MASetCanEncrypt:(BOOL)canEncrypt {
    // Only on Yosemite. See MASetCanSign for explanation.
    ComposeBackEnd *backEnd = [GPGMailBundle backEndFromObject:self];
    NSDictionary *securityProperties = ((ComposeBackEnd_GPGMail *)backEnd).securityProperties;
    if(securityProperties[@"EncryptIsPossible"])
        canEncrypt = [securityProperties[@"EncryptIsPossible"] boolValue];
    [self MASetCanEncrypt:canEncrypt];
}

- (void)MASecurityControlChanged:(NSControl *)securityControl {
    // 0x3e8 = 1000 = encrypt button
    // 0x7d0 = 2000 = sign button
    if([securityControl tag] == 2000) {
        // Toggle the current status.
        BOOL messageIsToBeSigned = ![mailself messageIsToBeSigned];
        ComposeViewController *composeViewController = [self composeViewController];
        ComposeBackEnd *backEnd = [composeViewController backEnd];
        [backEnd setSignIfPossible:messageIsToBeSigned];
        // Update the preferred security properties to reflect the user choice.
        // From this point on, the computed shouldEncryptMessage method, will always return the
        // value set for userShouldSignMessage.
        // Apple uses NSUserDefaults here instead, but that is not good enough for us.
        GMComposeMessagePreferredSecurityProperties *preferredSecurityProperties = [(ComposeBackEnd_GPGMail *)backEnd preferredSecurityProperties];
        preferredSecurityProperties.userShouldSignMessage = messageIsToBeSigned;
        [mailself setMessageIsToBeSigned:messageIsToBeSigned];
        [(MailDocumentEditor_GPGMail *)composeViewController updateSecurityMethodAccessoryView];
        [composeViewController updateAttachmentStatus];
    }
    else {
        [self performSelectorInBackground:@selector(_toggleEncryption) withObject:nil];
    }
}

- (void)MA_toggleEncryption {
    ComposeViewController *composeViewController = [self composeViewController];
    ComposeBackEnd *backEnd = [composeViewController backEnd];
    // This is implemented in Mail as:
    // mov        rsi, qword [ds:0x1004b22c0]                 ; @selector(messageIsToBeEncrypted), argument "selector" for method _objc_msgSend
    // mov        rdi, r12                                    ; argument "instance" for method _objc_msgSend
    // call       r13                                         ; _objc_msgSend
    // xor        ebx, ebx
    // test       al, al
    // sete       r15b
    //
    // Which in pseudo code reads:
    // rax = [r12 messageIsToBeEncrypted];
    // LODWORD(rbx) = 0x0;
    // LOBYTE(r15) = COND_BYTE_SET(E);
    //
    // And seems to simply do the following:
    BOOL messageIsToBeEncrypted = ![mailself messageIsToBeEncrypted];
    NSArray *recipientsWithNoKey = nil;
    
    if([mailself messageIsToBeEncrypted]) {
        recipientsWithNoKey = [backEnd recipientsThatHaveNoKeyForEncryption];
    }
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        // arg0 + 0x28 = composeViewController
        // arg0 + 0x20 = recipientsWithNoKey
        // arg0 + 0x30 = self
        // What is arg0 + 0x38? assuming it's r15 for now. Question is, is this value ever YES?
        if(messageIsToBeEncrypted == YES && [recipientsWithNoKey count]) {
            NSString *missingCertificatesErrorMessage = [composeViewController missingCertificatesMessageForRecipients:recipientsWithNoKey uponDelivery:NO];
            if(missingCertificatesErrorMessage) {
                NSAlert *missingCertificatesAlert = [NSAlert new];
                // TODO: Find out what _MFStringKeyErrorTitle resolves to.
                NSString *alertTitle = [[NSClassFromString(@"MailFramework") bundle] localizedStringForKey:@"MFStringKeyErrorTitle" value:@"" table:@"MailFramework"];
                [missingCertificatesAlert setMessageText:alertTitle];
                [missingCertificatesAlert setInformativeText:missingCertificatesErrorMessage];
                [missingCertificatesAlert beginSheetModalForWindow:[[composeViewController view] window] completionHandler:^(__unused NSModalResponse returnCode) {
                    [mailself setMessageIsToBeEncrypted:NO];
                }];
            }
            else {
                [backEnd setEncryptIfPossible:messageIsToBeEncrypted];
                // Update the preferred security properties to reflect the user choice.
                // From this point on, the computed shouldEncryptMessage method, will always return the
                // value set for userShouldSignMessage.
                // Apple uses NSUserDefaults here instead, but that is not good enough for us.
                GMComposeMessagePreferredSecurityProperties *preferredSecurityProperties = [(ComposeBackEnd_GPGMail *)backEnd preferredSecurityProperties];
                preferredSecurityProperties.userShouldEncryptMessage = messageIsToBeEncrypted;
                [mailself setMessageIsToBeEncrypted:messageIsToBeEncrypted];
            }
        }
        else {
            [backEnd setEncryptIfPossible:messageIsToBeEncrypted];
            // Update the preferred security properties to reflect the user choice.
            // From this point on, the computed shouldEncryptMessage method, will always return the
            // value set for userShouldSignMessage.
            // Apple uses NSUserDefaults here instead, but that is not good enough for us.
            GMComposeMessagePreferredSecurityProperties *preferredSecurityProperties = [(ComposeBackEnd_GPGMail *)backEnd preferredSecurityProperties];
            preferredSecurityProperties.userShouldEncryptMessage = messageIsToBeEncrypted;
            [mailself setMessageIsToBeEncrypted:messageIsToBeEncrypted];
        }
        [(MailDocumentEditor_GPGMail *)composeViewController updateSecurityMethodAccessoryView];
        [composeViewController updateAttachmentStatus];
        
//        r14 = arg0;
//        if ((*(int8_t *)(r14 + 0x38) != 0x0) && ([*(r14 + 0x20) count] != 0x0)) {
//            rax = [*(r14 + 0x28) missingCertificatesMessageForRecipients:*(r14 + 0x20) uponDelivery:0x0];
//            rax = [rax retain];
//            if (rax != 0x0) {
//                var_58 = rax;
//                var_68 = [NSAlert new];
//                r15 = _objc_msgSend;
//                r12 = [[MailFramework bundle] retain];
//                
//                r13 = [[r12 localizedStringForKey:*_MFStringKeyErrorTitle value:@"" table:@"MailFramework"] retain];
//                rax = [var_68 setMessageText:r13];
//                r15 = _objc_release;
//                rax = [r13 release];
//                rax = [r12 release];
//                r15 = r14 + 0x28;
//                rax = [var_68 setInformativeText:var_58];
//                r13 = _objc_msgSend;
//                r12 = [[*(r14 + 0x28) view] retain];
//                r13 = [[r12 window] retain];
//                var_48 = 0xc2000000;
//                var_44 = 0x0;
//                var_40 = sub_1001938ef;
//                var_38 = 0x1003e4cc0;
//                var_30 = [*(r14 + 0x30) retain];
//                rax = [var_68 beginSheetModalForWindow:r13 completionHandler:__NSConcreteStackBlock];
//                rbx = _objc_release;
//                rax = [r13 release];
//                rax = [r12 release];
//                rax = [var_30 release];
//                rax = [var_68 release];
//                rax = [var_58 release];
//            }
//            else {
//                r15 = r14 + 0x28;
//                r12 = _objc_msgSend;
//                rbx = [[*(r14 + 0x28) backEnd] retain];
//                rax = [rbx setEncryptIfPossible:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//                r13 = _objc_release;
//                rax = [rbx release];
//                rbx = [[MailApp sharedApplication] retain];
//                rax = [rbx setEncryptOutgoingMessages:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//                rax = [rbx release];
//                rax = [*(r14 + 0x30) setMessageIsToBeEncrypted:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//            }
//        }
//        else {
//            r15 = r14 + 0x28;
//            r12 = _objc_msgSend;
//            rbx = [[*(r14 + 0x28) backEnd] retain];
//            rax = [rbx setEncryptIfPossible:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//            r13 = _objc_release;
//            rax = [rbx release];
//            rbx = [[MailApp sharedApplication] retain];
//            rax = [rbx setEncryptOutgoingMessages:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//            rax = [rbx release];
//            rax = [*(r14 + 0x30) setMessageIsToBeEncrypted:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//        }
//        rax = [*r15 updateAttachmentStatus];
//        rbx = stack[2042];
//        r12 = stack[2043];
//        r13 = stack[2044];
//        r14 = stack[2045];
//        r15 = stack[2046];
//        rsp = rsp + 0x78;
//        rbp = stack[2047];
//        return;
    }];
    
//    r12 = self;
//    r13 = _objc_msgSend;
//    r14 = [[self composeViewController] retain];
//    rbx = 0x0;
//    r15 = COND_BYTE_SET(E);
//    if ([r12 messageIsToBeEncrypted] == 0x0) {
//        r13 = _objc_msgSend;
//        var_70 = r15;
//        r15 = [[r14 backEnd] retain];
//        rbx = [[r15 recipientsThatHaveNoKeyForEncryption] retain];
//        rdi = r15;
//        r15 = var_70;
//        [rdi release];
//    }
//    r13 = [(r13)(@class(NSOperationQueue), @selector(mainQueue)) retain];
//    var_48 = rbx;
//    var_70 = [rbx retain];
//    var_40 = r14;
//    r14 = [r14 retain];
//    var_38 = [r12 retain];
//    [r13 addOperationWithBlock:^{
//        r14 = arg0;
//        if ((*(int8_t *)(r14 + 0x38) != 0x0) && ([*(r14 + 0x20) count] != 0x0)) {
//            rax = [*(r14 + 0x28) missingCertificatesMessageForRecipients:*(r14 + 0x20) uponDelivery:0x0];
//            rax = [rax retain];
//            if (rax != 0x0) {
//                var_58 = rax;
//                var_68 = [NSAlert new];
//                r15 = _objc_msgSend;
//                r12 = [[MailFramework bundle] retain];
//                r13 = [[r12 localizedStringForKey:*_MFStringKeyErrorTitle value:@"" table:@"MailFramework"] retain];
//                rax = [var_68 setMessageText:r13];
//                r15 = _objc_release;
//                rax = [r13 release];
//                rax = [r12 release];
//                r15 = r14 + 0x28;
//                rax = [var_68 setInformativeText:var_58];
//                r13 = _objc_msgSend;
//                r12 = [[*(r14 + 0x28) view] retain];
//                r13 = [[r12 window] retain];
//                var_48 = 0xc2000000;
//                var_44 = 0x0;
//                var_40 = sub_1001938ef;
//                var_38 = 0x1003e4cc0;
//                var_30 = [*(r14 + 0x30) retain];
//                rax = [var_68 beginSheetModalForWindow:r13 completionHandler:__NSConcreteStackBlock];
//                rbx = _objc_release;
//                rax = [r13 release];
//                rax = [r12 release];
//                rax = [var_30 release];
//                rax = [var_68 release];
//                rax = [var_58 release];
//            }
//            else {
//                r15 = r14 + 0x28;
//                r12 = _objc_msgSend;
//                rbx = [[*(r14 + 0x28) backEnd] retain];
//                rax = [rbx setEncryptIfPossible:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//                r13 = _objc_release;
//                rax = [rbx release];
//                rbx = [[MailApp sharedApplication] retain];
//                rax = [rbx setEncryptOutgoingMessages:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//                rax = [rbx release];
//                rax = [*(r14 + 0x30) setMessageIsToBeEncrypted:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//            }
//        }
//        else {
//            r15 = r14 + 0x28;
//            r12 = _objc_msgSend;
//            rbx = [[*(r14 + 0x28) backEnd] retain];
//            rax = [rbx setEncryptIfPossible:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//            r13 = _objc_release;
//            rax = [rbx release];
//            rbx = [[MailApp sharedApplication] retain];
//            rax = [rbx setEncryptOutgoingMessages:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//            rax = [rbx release];
//            rax = [*(r14 + 0x30) setMessageIsToBeEncrypted:sign_extend_64(*(int8_t *)(r14 + 0x38))];
//        }
//        rax = [*r15 updateAttachmentStatus];
//        rbx = stack[2042];
//        r12 = stack[2043];
//        r13 = stack[2044];
//        r14 = stack[2045];
//        r15 = stack[2046];
//        rsp = rsp + 0x78;
//        rbp = stack[2047];
//        return;
//    }];
//    [r13 release];
//    [var_38 release];
//    [var_40 release];
//    [var_48 release];
//    [r14 release];
//    [var_70 release];
//    return;
}





// TODO: Remove - should no longer be necessary to implement at all
//- (void)MASetMessageIsToBeEncrypted:(BOOL)isToBeEncrypted {
//    ComposeBackEnd_GPGMail *backEnd = [GPGMailBundle backEndFromObject:self];
//    GMComposeMessagePreferredSecurityProperties *preferredSecurityProperties = backEnd.preferredSecurityProperties;
//    // -[HeadersEditor setMessageIsToBeEncrypted:] is called when the user presses
//    // the encrypt button. Once the user has formed a decision on whether or not to encrypt
//    // the message, the preferred security properties have to be updated to reflect that choice.
//    // From this point on, the computed shouldEncryptMessage method, will always return the
//    // value set for userShouldEncryptMessage.
//    preferredSecurityProperties.userShouldEncryptMessage = isToBeEncrypted;
//    
////    // On Yosemite, the encrypt and sign button states are no longer directly set
////    // in _updateSecurityStateInBackgroundForRecipients, but instead in setMessageIsToBeEncrypted.
////    // So we set our preferred state in here.
////    ComposeBackEnd *backEnd = [GPGMailBundle backEndFromObject:self];
////    NSDictionary *securityProperties = ((ComposeBackEnd_GPGMail *)backEnd).securityProperties;
////    
////    // It's possible that SetEncrypt is set to true, since that only reflects the defaults
////    // set by the user.
////    // If EncryptIsPossible (based on the availability of a public key) is true and
////    // the user set the default for EncryptNewMessagesByDefault to true (which is reflected by EncryptIsPossible)
////    // the message is in fact being encrypted and thus isToBeEncrypted is set to true.
////    // ForceEncrypt however reflects the user choice and is thus not questioned.
////    if(securityProperties[@"SetEncrypt"] && securityProperties[@"EncryptIsPossible"])
////        isToBeEncrypted = [securityProperties[@"SetEncrypt"] boolValue] && [securityProperties[@"EncryptIsPossible"] boolValue];
////    // ForceEncrypt overrides SetEncrypt since it reflects the user's choice.
////    if(securityProperties[@"ForceEncrypt"])
////        isToBeEncrypted = [securityProperties[@"ForceEncrypt"] boolValue];
////    // ForceEncrypt must be ignored if EncryptIsPossible is set to NO.
////    if(securityProperties[@"EncryptIsPossible"])
////        isToBeEncrypted = isToBeEncrypted && [securityProperties[@"EncryptIsPossible"] boolValue];
//    
//    [self MASetMessageIsToBeEncrypted:isToBeEncrypted];
//}

// TODO: Remove - should no longer be necessary.
//- (void)MASetMessageIsToBeSigned:(BOOL)isToBeSigned {
//    ComposeBackEnd_GPGMail *backEnd = [GPGMailBundle backEndFromObject:self];
//    GMComposeMessagePreferredSecurityProperties *preferredSecurityProperties = backEnd.preferredSecurityProperties;
//    // -[HeadersEditor setMessageIsToBeEncrypted:] is called when the user presses
//    // the encrypt button. Once the user has formed a decision on whether or not to encrypt
//    // the message, the preferred security properties have to be updated to reflect that choice.
//    // From this point on, the computed shouldEncryptMessage method, will always return the
//    // value set for userShouldEncryptMessage.
//    preferredSecurityProperties.userShouldSignMessage = isToBeSigned;
//
////    // On Yosemite, the encrypt and sign button states are no longer directly set
////    // in _updateSecurityStateInBackgroundForRecipients, but instead in setMessageIsToBeSigned.
////    // So we set our preferred state in here.
////    ComposeBackEnd *backEnd = [GPGMailBundle backEndFromObject:self];
////    NSDictionary *securityProperties = ((ComposeBackEnd_GPGMail *)backEnd).securityProperties;
////    
////    if(securityProperties[@"SetSign"])
////        isToBeSigned = [securityProperties[@"SetSign"] boolValue];
////    // ForceSign overrides SetSign since it reflects the user's choice.
////    if(securityProperties[@"ForceSign"])
////        isToBeSigned = [securityProperties[@"ForceSign"] boolValue];
////    // ForceSign must be ignored if SignIsPossible is set to NO.
////    if(securityProperties[@"SignIsPossible"])
////        isToBeSigned = isToBeSigned && [securityProperties[@"SignIsPossible"] boolValue];
//    
//    [self MASetMessageIsToBeSigned:isToBeSigned];
//}

- (void)updateFromAndAddSecretKeysIfNecessary:(NSNumber *)necessary {
    BOOL display = [necessary boolValue];
    NSPopUpButton *popUp = nil;
    popUp = [self fromPopup];
    
	NSMenu *menu = [popUp menu];
	NSArray *menuItems = [menu itemArray];
	GPGMailBundle *bundle = [GPGMailBundle sharedInstance];
	
    // Is used to properly truncate our own menu items.
    NSMutableParagraphStyle *truncateStyle = [[NSMutableParagraphStyle alloc] init];
    [truncateStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    [attributes addEntriesFromDictionary:[[menuItems[0] attributedTitle] fontAttributesInRange:NSMakeRange(0, [[menuItems[0] attributedTitle] length])]];
	attributes[NSParagraphStyleAttributeName] = truncateStyle;
    
	// Also use the proper styling for external addresses.
    NSPopUpButton *fromPopup = ![GPGMailBundle isYosemite] ? [self valueForKey:@"_fromPopup"] : [self fromPopup];
    NSFont *font = [NSFont menuFontOfSize:[[(NSPopUpButtonCell *)[fromPopup cell] font] pointSize]];
    NSMutableParagraphStyle *paragraphStyle = [NSMutableParagraphStyle new];
    [paragraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
    NSDictionary *externalAttributes = [[NSDictionary alloc] initWithObjectsAndKeys:
										[NSClassFromString(@"MUIAddressTokenAttachmentCell") colorForExternalDomain], NSForegroundColorAttributeName,
                                        font, NSFontAttributeName, nil];
	
	
	NSMenuItem *item, *parentItem, *selectedItem = [popUp selectedItem], *subItemToSelect = nil;
	GPGKey *defaultKey = [bundle preferredGPGKeyForSigning];
	BOOL useTitleFromAccount = [[GPGOptions sharedOptions] boolForKey:@"ShowAccountNameForKeysOfSameAddress"];
	
	// If menu items are not yet set, simply exit.
    // This might happen if securityMethodDidChange notification
    // is posted before the menu items have been configured.
    if(!menuItems.count || (menuItems.count == 1 && ![(NSMenuItem *)[menuItems objectAtIndex:0] representedObject]))
        return;
    
	menu.autoenablesItems = NO;
	
	NSUInteger count = [menuItems count], i = 0;
	NSDictionary *currentAttributes = attributes;
	
	for (; i < count; i++) {
		item = menuItems[i];
		parentItem = [item getIvar:kHeadersEditorFromControlParentItemKey];
		if (parentItem) {
			[menu removeItem:item]; // We remove all elements that represent a key.
		} else if (display) {
            NSString *itemTitle = item.title;
			
			NSString *email = nil;
			if (useTitleFromAccount == NO)
                email = ![GPGMailBundle isYosemite] ? [itemTitle gpgNormalizedEmail] : [item.representedObject gpgNormalizedEmail];
			
            NSString *address = [item.representedObject gpgNormalizedEmail];
            NSSet *keys = [bundle signingKeyListForAddress:address];
			switch ([keys count]) {
				case 0:
					// We have no key for this account.
					[item removeIvar:kHeadersEditorFromControlGPGKeyKey];
					item.hidden = NO;
					break;
				case 1:
					// We have only one key for this account: Set it.
					[item setIvar:kHeadersEditorFromControlGPGKeyKey value:[keys anyObject]];
					item.hidden = NO;
					break;
				default: {
					// We have more than one key for this account:
					// Add menu items to let the user choose.
					NSInteger index = [menu indexOfItem:item];
					
					for (GPGKey *key in keys) {
						NSMenuItem *subItem = nil;
						if (i + 1 < count && (subItem = menuItems[i + 1]) && [subItem getIvar:kHeadersEditorFromControlParentItemKey] && [subItem getIvar:kHeadersEditorFromControlGPGKeyKey] == key) {
							// The next item is the item we want to create: Jump over.
							i++;
							index++;
						} else {
							NSString *title;
							if (useTitleFromAccount) {
								title = [NSString stringWithFormat:@"%@ (%@)", itemTitle, [key.keyID shortKeyID]]; // Compose the title "Name <E-Mail> (KeyID)".
							} else {
                                if([GPGMailBundle isYosemite])
                                    title = [NSString stringWithFormat:@"%@ - %@ (%@)", key.name, email, [key.keyID shortKeyID]]; // Compose the title "key.Name - E-Mail (KeyID)".
                                else
                                    title = [NSString stringWithFormat:@"%@ <%@> (%@)", key.name, email, [key.keyID shortKeyID]]; // Compose the title "key.Name <E-Mail> (KeyID)".
							}
							
							currentAttributes = [NSClassFromString(@"MUITokenAddress") addressIsExternal:email] ? externalAttributes : attributes;
							
							NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:currentAttributes];

							// Create the menu item with the given title...
							subItem = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
							[subItem setAttributedTitle:attributedTitle];
							[subItem setIvar:kHeadersEditorFromControlGPGKeyKey value:key]; // GPGKey...
							[subItem setIvar:kHeadersEditorFromControlParentItemKey value:item]; // and set the parentItem.
                            [subItem setRepresentedObject:item.representedObject];
							[menu insertItem:subItem atIndex:++index]; // Insert it in the "From:" menu.
                        }
						if (item == selectedItem) {
							if (key == defaultKey) {
								subItemToSelect = subItem;
							}
						}
						
					}
					item.hidden = YES;
					break; }
			}
		} else { // display == NO
			// Restore all original items.
			[item removeIvar:kHeadersEditorFromControlGPGKeyKey];
			item.hidden = NO;
		}
	}
	
	ComposeBackEnd *backEnd = [GPGMailBundle backEndFromObject:self];
	
    // Select a valid item if needed.
    if (selectedItem.isHidden) {
		NSUInteger index;
		if (subItemToSelect) {
			index = [menu indexOfItem:subItemToSelect];
		} else {
			index = [menu indexOfItem:selectedItem] + 1;
		}
        [popUp selectItemAtIndex:index];
        [popUp synchronizeTitleAndSelectedItem];
		
		[popUp setIvar:@"CalledFromGPGMail" value:@YES];
		[self changeFromHeader:popUp];
    }
    else if ([popUp selectedItem] != selectedItem) {
        if ((parentItem = [selectedItem getIvar:kHeadersEditorFromControlParentItemKey])) {
            selectedItem = parentItem;
        }
        [popUp selectItem:selectedItem];
        [popUp synchronizeTitleAndSelectedItem];
		
		[popUp setIvar:@"CalledFromGPGMail" value:@YES];
        [self changeFromHeader:popUp];
    } else if (![backEnd getIvar:@"gpgKeyForSigning"]) {
		id gpgKey = [selectedItem getIvar:kHeadersEditorFromControlGPGKeyKey];
		if (gpgKey) {
			[backEnd setIvar:@"gpgKeyForSigning" value:gpgKey];
		}
	}
}

- (void)MAChangeFromHeader:(NSPopUpButton *)sender {
    BOOL calledFromGPGMail = [[sender getIvar:@"CalledFromGPGMail"] boolValue];
    [sender setIvar:@"CalledFromGPGMail" value:@NO];
    
    // Create a new NSPopUpButton with only one item and the correct title.
	NSPopUpButton *button = [[NSPopUpButton alloc] init];
	NSMenuItem *item = [sender selectedItem];
	NSMenuItem *parentItem = [item getIvar:kHeadersEditorFromControlParentItemKey];
    
    // On Yosemite, the representedObject contains the fullAddress (name <email>) of the
    // menu item. If we use addItemWithTitle, the representedObject is no longer set,
    // and mail receives nil when querying the address and thus can't properly set the sender.
    // In order to fix this, we simply use addItem: on the button's menu instead.
    if([GPGMailBundle isYosemite]) {
        // Since according to the documentation, a menuitem must not belong to another menu,
        // we have to create a new version with the same properties.
        NSMenuItem *baseItem = parentItem ? parentItem : item;
        NSMenuItem *fakeItem = [[NSMenuItem alloc] init];
        fakeItem.attributedTitle = baseItem.attributedTitle;
        fakeItem.representedObject = baseItem.representedObject;
        [[button menu] addItem:fakeItem];
    }
    else
        [button addItemWithTitle:(parentItem ? parentItem : item).title];
    
    // Set the selected key in the back-end.
	ComposeBackEnd *backEnd = [GPGMailBundle backEndFromObject:self];
	[backEnd setIvar:@"gpgKeyForSigning" value:[item getIvar:kHeadersEditorFromControlGPGKeyKey]];
    
    [self MAChangeFromHeader:button];
}

- (void)keyringUpdated:(NSNotification *)notification {
    // Will always be called on the main thread!.
	if(![NSThread isMainThread]) {
		DebugLog(@"%@: not called on main thread? What the fuck?!", NSStringFromSelector(_cmd));
		return;
	}
	
	ComposeBackEnd *backEnd = [GPGMailBundle backEndFromObject:self];
	GPGMAIL_SECURITY_METHOD securityMethod = ((ComposeBackEnd_GPGMail *)backEnd).guessedSecurityMethod;
    if(((ComposeBackEnd_GPGMail *)backEnd).securityMethod)
        securityMethod = ((ComposeBackEnd_GPGMail *)backEnd).securityMethod;
	// It seems calling updateSecurityControls at this point is most reliable.
    if([GPGMailBundle isYosemite]) {
        [self _updateSecurityControls];
    }
    else {
        [self updateSecurityControls];
    }
}

- (void)updateEncryptAndSignButtonToolTips {
    // This method is currently only used on Yosemite, since Apple
    // switched to a ValueTransformer which is not really adequate for
    // our more advanced tool tips.
    ComposeBackEnd_GPGMail *backEnd = [GPGMailBundle backEndFromObject:self];
    GPGMAIL_SECURITY_METHOD securityMethod = backEnd.securityMethod;
    if(securityMethod == 0)
        securityMethod = backEnd.guessedSecurityMethod;
    
    if(securityMethod != GPGMAIL_SECURITY_METHOD_OPENPGP)
        return;
    
    NSString *signToolTip = [self signButtonToolTip];
    GMSecurityControl *signControl = [self valueForKey:@"_signButton"];
    [((NSSegmentedControl *)signControl) setToolTip:signToolTip];
    
    NSString *encryptToolTip = [self encryptButtonToolTip];
    GMSecurityControl *encryptControl = [self valueForKey:@"_encryptButton"];
    [((NSSegmentedControl *)encryptControl) setToolTip:encryptToolTip];
}

- (void)MA_updateSignButtonTooltip {
    // This was replaced by a ValueTransformer in Yosemite.
    // The NSSegmentedControl encryptButton and signButton have a binding for toolTip
    // which can be queried like this.
    // [[[self signButton] control] infoForBinding:@"toolTip"];
    // Basically replacing it with our own value might suffice.
    // Or we could simply unbind it and call our own methods which will set the
    // tooltips directly.
    // Seems to be the easier way.
    // So basically.
    // [[[self signButton] control] unbind:@"toolTip"];
    // [[[self signButton] control] setToolTip:@"Whatever we want to be written here."];
    // The binding listens to messageIsToBeEncrypted and messageIsToBeSigned, so maybe we should as well.
    
    ComposeBackEnd_GPGMail *backEnd = [GPGMailBundle backEndFromObject:self];
    if(backEnd.securityMethod == GPGMAIL_SECURITY_METHOD_OPENPGP) {
        NSString *signToolTip = [self signButtonToolTip];
        GMSecurityControl *signControl = [self valueForKey:@"_signButton"];
        [((NSSegmentedControl *)signControl) setToolTip:signToolTip];
    }
    else {
        [self MA_updateSignButtonTooltip];
    }
}

- (NSString *)encryptButtonToolTip {
    ComposeBackEnd_GPGMail *backEnd = [GPGMailBundle backEndFromObject:self];
    NSDictionary *securityProperties = ((ComposeBackEnd_GPGMail *)backEnd).securityProperties;
    
    NSString *toolTip = @"";
    
    if(![securityProperties[@"EncryptIsPossible"] boolValue]) {
        NSArray *nonEligibleRecipients = [(ComposeBackEnd *)backEnd recipientsThatHaveNoKeyForEncryption];
        if(![nonEligibleRecipients count])
            toolTip = GMLocalizedString(@"COMPOSE_WINDOW_TOOLTIP_CAN_NOT_PGP_ENCRYPT_NO_RECIPIENTS");
        else {
            NSString *recipients = [nonEligibleRecipients componentsJoinedByString:@", "];
            toolTip = [NSString stringWithFormat:GMLocalizedString(@"COMPOSE_WINDOW_TOOLTIP_CAN_NOT_PGP_ENCRYPT"), recipients];
        }
    }
    
    return toolTip;
}

- (NSString *)signButtonToolTip {
    ComposeBackEnd_GPGMail *backEnd = [GPGMailBundle backEndFromObject:self];
    NSDictionary *securityProperties = ((ComposeBackEnd_GPGMail *)backEnd).securityProperties;
    
    NSString *toolTip = @"";
    
    if(![securityProperties[@"SignIsPossible"] boolValue]) {
        NSPopUpButton *button = [self valueForKey:@"_fromPopup"];
        NSString *sender = ![GPGMailBundle isYosemite] ? [button.selectedItem.title gpgNormalizedEmail] : [button.selectedItem.representedObject gpgNormalizedEmail];
        
        if([sender length] == 0 && [button.itemArray count])
            sender = ![GPGMailBundle isYosemite] ? [[(button.itemArray)[0] title] gpgNormalizedEmail] : [[(button.itemArray)[0] representedObject] gpgNormalizedEmail];
        
        toolTip = [NSString stringWithFormat:GMLocalizedString(@"COMPOSE_WINDOW_TOOLTIP_CAN_NOT_PGP_SIGN"), sender];
    }
    
    return toolTip;
}

- (void)MA_updateEncryptButtonTooltip {
    ComposeBackEnd_GPGMail *backEnd = [GPGMailBundle backEndFromObject:self];
    
    GPGMAIL_SECURITY_METHOD securityMethod = backEnd.guessedSecurityMethod;
    if(backEnd.securityMethod)
        securityMethod = backEnd.securityMethod;
    
    if(securityMethod == GPGMAIL_SECURITY_METHOD_OPENPGP) {
        NSString *encryptToolTip = [self encryptButtonToolTip];
        GMSecurityControl *encryptControl = [self valueForKey:@"_encryptButton"];
        [((NSSegmentedControl *)encryptControl) setToolTip:encryptToolTip];
    }
    else {
        [self MA_updateEncryptButtonTooltip];
    }
}

- (void)MADealloc {
    @try {
//        [(MailNotificationCenter *)[NSClassFromString(@"MailNotificationCenter") defaultCenter] removeObserver:self];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
    @catch (id e) {
    }
	[self MADealloc];
}

// TODO: Test-Swizzle. Propably not necessary. Remove

- (void)MA_setVisibilityForEncryptionAndSigning:(BOOL)arg1 {
    [self MA_setVisibilityForEncryptionAndSigning:arg1];
}

@end

#undef mailself

/* ORIGINAL SOURCE OF MAIL.APP FOR LEARING. */

//- (void)configureButtonsAndPopUps {
//    WebViewEditor *webViewEditor = [[self valueForKey:@"_documentEditor"] webViewEditor];
//	[webViewEditor updateIgnoredWordsForHeader:NO];
//	[webViewEditor updateSecurityControls];
//	[webViewEditor updatePriorityPopUpMakeActive:YES];
//
//	ComposeBackEnd *backEnd = [self _valueForKey:@"_documentEditor"];
//	long long messagePriority = [backEnd displayableMessagePriority];
//
//	if(messagePriority != 3) {
//		if([[self valueForKey:@"_priorityPopup"] isHiddenOrHasHiddenAncestor])
//		   [[self valueForKey:@"_composeHeaderView"] setPriorityFieldVisible:YES];
//	}
//
//	[self _updateFromAndSignatureControls];
//}
//
//- (void)changeHeaderField:(id)headerField {
//	NSString *headerKey = [self _headerKeyForView:headerField];
//	if(!headerKey)
//		return;
//
//	if([self valueForKey:@"_subjectField"] != headerField) {
//		NSString *attributedStringValue = [headerField attributedStringValue];
//		NSString *unatomicAddress = [attributedStringValue unatomicAddresses];
//		[[[self valueForKey:@"_documentEditor"] backEnd] setAddressList:unatomicAddress forHeader:headerKey];
//
//		if([self valueForKey:@"_toField"] != headerField && [self valueForKey:@"_ccField"] != headerField) {
//			if([self valueForKey:@"_bccField"] == headerField) {
//				[[self valueForKey:@"_documentEditor"] updateSendButtonStateInToolbar];
//				[self updateSecurityControls];
//				[self updatePresenceButtonState];
//			}
//			else
//				return;
//		}
//		else {
//			[[self valueForKey:@"_documentEditor"] updateSendButtonStateInToolbar];
//			[self updateSecurityControls];
//			[self updatePresenceButtonState];
//		}
//	}
//}
//
//- (void)changeFromHeader:(id)header {
//	ComposeBackEnd *backEnd = [[self valueForKey:@"_documentEditor"] backEnd]; // r15
//	NSString *title = [header titleOfSelectedItem];
//	if(title) {
//		NSString *sender = [backEnd sender];
//		[sender retain];
//		[backEnd setSender:title];
//		[self updateCcOrBccMyselfFieldWithSender:title oldSender:sender];
//		[sender release];
//		[self updateSecurityControls];
//		[self updateSignatureControlOverridingExistingSignature:YES];
//		[[self valueForKey:@"_documentEditor"] updateAttachmentStatus];
//	}
//	// And some more stuff which shall not be our concern currently.
//
//}
//
//- (void)updateSecurityControls {
//	ComposeBackEnd *backEnd = [[self valueForKey:@"_documentEditor"] backEnd];
//	NSArray *recipients = [backEnd allRecipients];
//	NSString *sender = [backEnd sender];
//    NSInvocation *invocation = [NSInvocation invocationWithSelector:@selector(_updateSecurityStateInBackgroundForRecipients:sender:) target:self object1:recipients	object2:sender];
//
//	[WorkerThread addInvocationToQueue:invocation];
//}
//
//- (void)_updateSecurityStateInBackgroundForRecipients:(id)recipients sender:(id)sender {
//	BOOL canSignFromAnyAccount = [self canSignFromAnyAccount];
//
//	BOOL canSignFromAddress = NO;
//	BOOL canEncryptFromAddress = NO;
//	if(canSignFromAnyAccount) {
//		ComposeBackEnd *backEnd = [[self valueForKey:@"_documentEditor"] backEnd];
//		canSignFromAddress = [backEnd canSignFromAddress:sender];
//		if(canSignFromAddress) {
//			canEncryptFromAddress = [backEnd canEncryptForRecipients:recipients sender:sender];
//		}
//	}
//	[[NSOperationQueue mainQueue] addOperationWithBlock:^{
//		[[self valueForKey:@"_composeHeaderView"] setSecurityFieldEnabled:canSignFromAddress];
//		if(canSignFromAddress && canEncryptFromAddress) {
//			if(![[self valueForKey:@"_composeHeaderView"] securityFieldVisible]) {
//				[[self valueForKey:@"_signButton"] setImage:@"" forSegment:0];
//				[[self valueForKey:@"_encryptButton"] setImage:@"" forSegment:0];
//				[[self valueForKey:@"_signButton"] setEnabled:NO];
//				[[self valueForKey:@"_encryptButton"] setEnabled:NO];
//
//				[[[self valueForKey:@"_documentEditor"] backEnd] setSignIfPossible:NO];
//			}
//			else {
//				BOOL sign = (BOOL)[NSApp signOutgoingMessages]; // r15
//				BOOL encrypt = (BOOL)[NSApp encryptOutgoingMessages];
//
//				NSImage *signImage = nil; // some image.
//				NSImage *encryptImage = nil; // some other image.
//				if(sign) {
//					signImage = nil; // different image
//				}
//
//				[[self valueForKey:@"_signButton"] setImage:signImage forSegment:0];
//				[[self valueForKey:@"_signButton"] setEnabled:YES];
//				[[[self valueForKey:@"_documentEditor"] backEnd] setSignIfPossible:sign];
//
//				if(!canEncryptFromAddress) {
//					[[self valueForKey:@"_encryptButton"] setEnabled:canEncryptFromAddress];
//					[[self valueForKey:@"_encryptButton"] setImage:encryptImage forSegment:0];
//
//					[[[self valueForKey:@"_documentEditor"] backEnd] setEncryptIfPossible:NO];
//				}
//				else {
//					[[self valueForKey:@"_encryptButton"] setEnabled:YES];
//
//					NSImage *encryptImage = nil; // some image.
//					if(encrypt)
//						encryptImage = nil; // some other image.
//					[[self valueForKey:@"_encryptButton"] setImage:encryptImage forSegment:0];
//					[[[self valueForKey:@"_documentEditor"] backEnd] setEncryptIfPossible:encrypt];
//
//					[self _updateSignButtonTooltip];
//					[self _updateEncryptButtonTooltip];
//
//					[[self valueForKey:@"_documentEditor"] encryptionStatusDidChange];
//				}
//			}
//		}
//	}];
//}


