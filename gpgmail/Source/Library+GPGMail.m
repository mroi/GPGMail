/* Library+GPGMail.m created by Lukas Pitschl (@lukele) on Wed 13-Jun-2013 */

/*
 * Copyright (c) 2000-2013, GPGTools Team <team@gpgtools.org>
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *     * Neither the name of GPGTools nor the names of GPGMail
 *       contributors may be used to endorse or promote products
 *       derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE GPGTools Team ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE GPGTools Team BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "CCLog.h"

#import "Library+GPGMail.h"
#import "NSObject+LPDynamicIvars.h"
#import "GPGFlaggedString.h"

#import "MFLibrary.h"
#import "MCMessage.h"
#import "MCMimeBody.h"
#import "MCMimePart.h"

#import "MCAttachment.h"
#import "MFLibraryAttachmentDataSource.h"
#import "MFLibraryMessage.h"

#import "MimePart+GPGMail.h"

#import "MCMessageGenerator.h"
#import "MCMutableMessageHeaders.h"
#import "MCOutgoingMessage.h"

#import "MimeBody+GPGMail.h"

#import "MFEWSStore.h"
#import "IMAPMessageDataSource-Protocol.h"
#import "MCParsedMessage.h"
#import "MFRemoteURLAttachmentDataSource.h"
#import "MFLibraryAttachmentDataSource.h"
#import "MFRemoteAttachmentDataSource.h"
#import "MCDataAttachmentDataSource.h"
#import "MCFileWrapperAttachmentDataSource.h"
#import "MCFileURLAttachmentDataSource.h"
#import "MCStationeryCompositeImage.h"

#import "GPGMailBundle.h"

#define MAIL_SELF(self) ((MFLibrary *)(self))

extern NSString *MCDescriptionForMessageFlags(int arg0);
extern const NSString *kMimeBodyMessageKey;
extern NSString * const kMimePartAllowPGPProcessingKey;

NSString * const kLibraryMimeBodyReturnCompleteBodyDataKey = @"LibraryMimeBodyReturnCompleteBodyDataKey";
NSString * const kLibraryMimeBodyReturnCompleteBodyDataForMessageKey = @"LibraryMimeBodyReturnCompleteBodyDataForMessageKey";
extern NSString * const kLibraryMimeBodyReturnCompleteBodyDataForComposeBackendKey;

NSString * const kLibraryMessagePreventSnippingAttachmentDataKey = @"LibraryMessagePreventSnippingAttachmentDataKey";

@implementation Library_GPGMail

/** ONLY FOR Mavericks and then on MFLibrary. */
+ (id)MAPlistDataForMessage:(id)message subject:(id)subject sender:(id)sender to:(id)to dateSent:(id)dateSent dateReceived:(id)dateReceived dateLastViewed:(id)dateLastViewed remoteID:(id)remoteID originalMailboxURLString:(id)originalMailboxURLString gmailLabels:(id)gmailLabels flags:(long long)flags mergeWithDictionary:(id)mergeWithDictionary {
    if([sender isKindOfClass:[GPGFlaggedString class]])
        sender = [(GPGFlaggedString *)sender description];
    if([to isKindOfClass:[GPGFlaggedString class]])
        to = [(GPGFlaggedString *)to description];
    
    return [self MAPlistDataForMessage:message subject:subject sender:sender to:to dateSent:dateSent dateReceived:dateReceived dateLastViewed:dateLastViewed remoteID:remoteID originalMailboxURLString:originalMailboxURLString gmailLabels:gmailLabels flags:flags mergeWithDictionary:mergeWithDictionary];
}

+ (id)MAPlistDataForMessage:(id)message subject:(id)subject sender:(id)sender to:(id)to dateSent:(id)dateSent remoteID:(id)remoteID originalMailbox:(id)originalMailbox flags:(long long)flags mergeWithDictionary:(id)mergeWithDictionary {
    if([sender isKindOfClass:[GPGFlaggedString class]])
        sender = [(GPGFlaggedString *)sender description];
    if([to isKindOfClass:[GPGFlaggedString class]])
        to = [(GPGFlaggedString *)to description];
    
    return [self MAPlistDataForMessage:message subject:subject sender:sender to:to dateSent:dateSent remoteID:remoteID originalMailbox:originalMailbox flags:flags mergeWithDictionary:mergeWithDictionary];
}

+ (NSData *)GMDataForMessage:(MCMessage *)message mimePart:(MCMimePart *)mimePart fetchIfNotAvailable:(BOOL)fetchIfNotAvailable {
    MCAttachment *attachment = [[MCAttachment alloc] initWithMimePart:mimePart];
    MFLibraryAttachmentDataSource *dataSource = [[MFLibraryAttachmentDataSource alloc] initWithMessage:message mimePartNumber:[mimePart partNumber] attachment:attachment remoteDataSource:nil];
    
    // Not available and should not be fetched, out of here.
    if(![dataSource dataIsLocallyAvailable] && !fetchIfNotAvailable) {
        return nil;
    }

    __block dispatch_semaphore_t waiter = dispatch_semaphore_create(0);
    __block NSData *attachmentData = nil;
    [dataSource dataForAccessLevel:1 completionBlock:^(NSData *data){
        attachmentData = data;
        dispatch_semaphore_signal(waiter);
    }];
    dispatch_semaphore_wait(waiter, DISPATCH_TIME_FOREVER);
    
    return attachmentData;
}

+ (NSData *)localMessageDataForMessage:(MCMessage *)message mimeBody:(MCMimeBody *)mimeBody error:(__autoreleasing NSError **)error {
    // MCMessageGenerator is usually used for building Outgoing Messages so it should
    // be very suitable for this task.

    // The mime tree is already available, so basically the only thing left to do, is
    // build the NSMapTable with the partData for the mime tree.
    __block NSMapTable *partData = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory capacity:0];

    MCMimePart *topLevelPart = [mimeBody topLevelPart];
    __block NSError *partError = nil;
    
    [(MimePart_GPGMail *)topLevelPart enumerateSubpartsWithBlock:^(MCMimePart *mimePart) {
        NSData *partBodyData = nil;
        if([mimePart isAttachment]) {
            partBodyData = [[self class] GMDataForMessage:message mimePart:mimePart fetchIfNotAvailable:NO];
            if(!partBodyData) {
                // If the data of an attachment is missing, abort. This means that the attachment
                // or for now the entire message has to be re-fetched.
                partError = [NSError errorWithDomain:@"GMAttachmentMissingError" code:201000 userInfo:nil];
                return;
            }
            if([[mimePart.contentTransferEncoding lowercaseString] isEqualToString:@"base64"]) {
                partBodyData = [partBodyData base64EncodedDataWithOptions:NSDataBase64Encoding76CharacterLineLength];
            }
        }
        else {
            // For partial emlx files, the top level part encodedBodyDay returns the entire
            // mime tree. Using decodedData, it's possible to check, if the part really contains data.
            // Only in that case, the encodedBodyData is added to the message data.
            partBodyData = [mimePart decodedData];
            if(partBodyData) {
                partBodyData = [mimePart encodedBodyData];
            }
        }
        if(partBodyData) {
            [partData setObject:partBodyData forKey:mimePart];
        }
    }];
    
    if(partError) {
        *error = partError;
        return nil;
    }
    
    MCMessageGenerator *messageGenerator = [[MCMessageGenerator alloc] init];
    MCMutableMessageHeaders *messageHeaders = [[MCMutableMessageHeaders alloc] initWithHeaderData:[topLevelPart headerData] encodingHint:NSUTF8StringEncoding];
    MCOutgoingMessage *outgoingMessage = [messageGenerator _newOutgoingMessageFromTopLevelMimePart:topLevelPart topLevelHeaders:messageHeaders withPartData:partData];

    return [outgoingMessage rawData];
}

+ (NSData *)forceFetchMessageDataForMessage:(MCMessage *)message {
    return [message messageDataIncludingFromSpace:YES newDocumentID:nil fetchIfNotAvailable:YES];
}

+ (MCMimeBody *)MAMimeBodyForMessage:(MCMessage *)currentMessage {
    // This method is responsible for fetching the complete message data
    // in case it's not yet available, or re-construct it from the locally cached data.
    // It's only allowed to do so however, if a user actively selected a message, in which
    // case it's invoked from -[RedundantContentIdentificationManager redundantContentMarkupForMessage:inConversation:]
    // and the current thread dictionary has the ReturnCompleteBodyData and the ReturnCompleteBodyDataForMessage message reference set.
    BOOL wantsCompleteBodyData = ([[[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataKey] boolValue] &&
                                 [[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataForMessageKey] == currentMessage) || [[[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataForComposeBackendKey] boolValue];
    MCMimeBody *mimeBody = [self MAMimeBodyForMessage:currentMessage];
    if(!wantsCompleteBodyData) {
        return mimeBody;
    }

    // It appears that if [MFLibraryMesage shouldSnipAttachmentData] returns NO,
    // Mail in 10.12.4 does fetch the entire emlx again (in case the message is multipart/signed. So if the entire message is available,
    // there's no need to rebuild it.
    NSString *messagePath = [MFLibrary _dataPathForMessage:currentMessage type:0];
    BOOL shouldRebuildMessage = [(MimeBody_GPGMail *)mimeBody mightContainPGPData] && ![MFLibrary _messageDataAtPath:messagePath];
    // Only if the message might contain PGP data, it's necessary for GPGMail to rebuild it
    // so the entire message is available for parsing.
    // The only case that should fall through for the moment is, if single parts of the message
    // are encrypted (as one mail service did).
    // Since at this point it's clear however, that the user did actively select a message,
    // GPGMail is allowed to act on PGP encrypted data, if it finds some (for example inline PGP in
    // text parts).
    if(!shouldRebuildMessage) {
        [[mimeBody topLevelPart] setIvar:kMimePartAllowPGPProcessingKey value:@(YES)];
        [mimeBody setIvar:kMimeBodyMessageKey value:currentMessage];
        return mimeBody;
    }

    __block dispatch_semaphore_t waiter = dispatch_semaphore_create(0);
    GPGMailBundle *bundle = [GPGMailBundle sharedInstance];

    __block NSLock *messageLock = nil;
    [[bundle messageBodyDataLoadingQueue] addOperationWithBlock:^{
        messageLock = [bundle.messageBodyDataLoadingCache objectForKey:messagePath];
        if(!messageLock) {
            messageLock = [[NSLock alloc] init];
            [bundle.messageBodyDataLoadingCache setObject:messageLock forKey:messagePath];
        }

        dispatch_semaphore_signal(waiter);
    }];
    dispatch_semaphore_wait(waiter, DISPATCH_TIME_FOREVER);
    dispatch_release(waiter);

    NSData *messageData = nil;
    @try {
        [messageLock lock];
        // Unfortunately the assumption that Mail always fetches the entire message in case
        // of multipart/signed messages seems to be wrong. Not sure whether it was luck but
        // in previous tests it worked reliably, now it does sometimes, sometimes not.
        // So the next attempt is to force fetch the entire message, if the message might
        // contain multipart/signed data.
        // Since the workaround to not snip the attachment data should work, the fetch should only happen
        // once, after that the entire .emlx file should be available.
        BOOL mightContainPGPData = [(MimeBody_GPGMail *)mimeBody mightContainPGPMIMESignedData];
        if(mightContainPGPData) {
            messageData = [self forceFetchMessageDataForMessage:currentMessage];
        }
        else {
            NSError *error = nil;
            messageData = [self localMessageDataForMessage:currentMessage mimeBody:mimeBody error:&error];
            if(!messageData && error) {
                messageData = [self forceFetchMessageDataForMessage:currentMessage];
            }
        }
    }
    @catch(NSException *e) {}
    @finally {
        [messageLock unlock];
        [[bundle messageBodyDataLoadingQueue] addOperationWithBlock:^{
            [bundle.messageBodyDataLoadingCache removeObjectForKey:messagePath];
        }];
    }

    if(!messageData) {
        [mimeBody setIvar:kMimeBodyMessageKey value:currentMessage];
        return mimeBody;
    }

    //NSLog(@"Fetched data: %lu", (unsigned long)[messageData length]);
    MCMimePart *mimePart = [[MCMimePart alloc] initWithEncodedData:messageData];
    mimeBody = [MCMimeBody new];
    [mimePart setIvar:kMimePartAllowPGPProcessingKey value:@(YES)];
    [mimeBody setTopLevelPart:mimePart];
    [mimePart setMimeBody:mimeBody];
    [mimePart parse];
    [mimeBody setIvar:kMimeBodyMessageKey value:currentMessage];
    return mimeBody;
}

+ (id)MAParsedMessageForMessage:(MFLibraryMessage *)message {
    MCMimeBody *mimeBody = [[MAIL_SELF(self) class] mimeBodyForMessage:message];
    BOOL wantsCompleteBodyData = ([[[[NSThread currentThread] threadDictionary] valueForKey:(NSString *)kLibraryMimeBodyReturnCompleteBodyDataKey] boolValue] &&
                                 [[[NSThread currentThread] threadDictionary] valueForKey:(NSString *)kLibraryMimeBodyReturnCompleteBodyDataForMessageKey] == message) || [[[[NSThread currentThread] threadDictionary] valueForKey:(NSString *)kLibraryMimeBodyReturnCompleteBodyDataForComposeBackendKey] boolValue];
    if(!mimeBody || !wantsCompleteBodyData) {
        return [self MAParsedMessageForMessage:message];
    }
    MCParsedMessage *parsedMessage = [mimeBody parsedMessage];
    // Check if there's a decrypted mimeBody on the mimeBody.
    NSError *error = nil;
    MCMimeBody *decryptedMimeBody = [[mimeBody topLevelPart] decryptedMimeBodyIsEncrypted:NULL isSigned:NULL error:&error];
    if(decryptedMimeBody && !error) {
        return [decryptedMimeBody parsedMessage];
    }

    // Setup the data source for attachments as Mail does.
    id <IMAPMessageDataSource> messageDataSource = [message dataSource];
    BOOL needRemoteDataSource = YES;
    if(![messageDataSource conformsToProtocol:@protocol(IMAPMessageDataSource)]) {
        needRemoteDataSource = [messageDataSource isKindOfClass:[MFEWSStore class]] ? YES : NO;
    }

    for(id key in [parsedMessage attachmentsByURL]) {
        MCAttachment *attachment = [[parsedMessage attachmentsByURL] objectForKey:key];
        // In some cases the data source for the attachment is already setup, for example
        // if a pgp encrypted attachment was decrypted.
        // In that case the data source *must no* be setup again.
        // Passing 0 to -[MCAttachment dataForAccessLevel:] guarantees that data is only returned,
        // if it's available locally.
        if([attachment dataForAccessLevel:0]) {
            continue;
        }
        id <MCRemoteAttachmentDataSource> remoteDataSource = nil;
        MFLibraryAttachmentDataSource *dataSource = nil;
        NSString *partNumber = [attachment mimePartNumber];
        if([attachment isRemotelyAccessed]) {
            NSString *attachmentsDirectory = [MFLibrary attachmentsDirectoryForMessage:message partNumber:partNumber];
            remoteDataSource = [[MFRemoteURLAttachmentDataSource alloc] initWithAttachment:attachment attachmentsDirectory:attachmentsDirectory];
        }
        else {
            if(needRemoteDataSource) {
                remoteDataSource = [MFRemoteAttachmentDataSource remoteAttachmentDataSourceForMessage:message];
            }
        }
        dataSource = [[MFLibraryAttachmentDataSource alloc] initWithMessage:message mimePartNumber:partNumber attachment:attachment remoteDataSource:remoteDataSource];
        [attachment setDataSource:dataSource];
        if(![attachment isRemotelyAccessed]) {
            [attachment setDownloadProgress:[(MFRemoteAttachmentDataSource *)remoteDataSource downloadProgress]];
        }
    }

    return parsedMessage;
}

+ (void)MASetData:(id)data forMessage:(id)message isPartial:(BOOL)isPartial hasCompleteText:(BOOL)hasCompleteText {
    // Since 10.12.4 it seems possible to force Mail to fetch the entire message body again for multipart/signed messages,
    // by returning NO from -[MFLibraryMessage shouldSnipAttachmentData].
    // In -[MFLibraryMessage shouldSnipAttachmentData] the data is however not available, which is the reason
    // why it's necessary to instruct -[MFLibraryMessage shouldSnipAttachmentData] to return NO, if a multipart/signed message
    // was found by setting an ivar on the message itself.
    MCMimePart *mimePart = [[MCMimePart alloc] initWithEncodedData:data];
    MCMimeBody *mimeBody = [MCMimeBody new];
    [mimeBody setTopLevelPart:mimePart];
    [mimePart setMimeBody:mimeBody];
    [mimePart parse];
    // Check if the message contains a PGP/MIME signature.
    BOOL mightContainPGPData = [(MimeBody_GPGMail *)mimeBody mightContainPGPMIMESignedData];
    if(mightContainPGPData) {
        [message setIvar:kLibraryMessagePreventSnippingAttachmentDataKey value:@(YES)];
    }
    [self MASetData:data forMessage:message isPartial:isPartial hasCompleteText:hasCompleteText];
}

@end
