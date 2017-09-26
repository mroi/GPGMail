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

// 10.13
#import "NSData-MailCoreAdditions.h"

#define MAIL_SELF(self) ((MFLibrary *)(self))

extern NSString *MCDescriptionForMessageFlags(int arg0);
extern const NSString *kMimeBodyMessageKey;
extern NSString * const kMimePartAllowPGPProcessingKey;

NSString * const kLibraryMimeBodyReturnCompleteBodyDataKey = @"LibraryMimeBodyReturnCompleteBodyDataKey";
NSString * const kLibraryMimeBodyReturnCompleteBodyDataForMessageKey = @"LibraryMimeBodyReturnCompleteBodyDataForMessageKey";
extern NSString * const kLibraryMimeBodyReturnCompleteBodyDataForComposeBackendKey;

NSString * const kLibraryMessagePreventSnippingAttachmentDataKey = @"LibraryMessagePreventSnippingAttachmentDataKey";

extern NSString * const kMessageSecurityFeaturesKey;

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
    [dataSource dataForAccessLevel:1 completionBlock:^(NSData *data, NSError *error){
        attachmentData = data;
        dispatch_semaphore_signal(waiter);
    }];
    dispatch_semaphore_wait(waiter, DISPATCH_TIME_FOREVER);
    
    return attachmentData;
}

+ (NSData *)GMLocalMessageDataForMessage:(MCMessage *)message topLevelPart:(MCMimePart *)topLevelPart error:(__autoreleasing NSError **)error {
    // MCMessageGenerator is usually used for building Outgoing Messages so it should
    // be very suitable for this task.

    // The mime tree is already available, so basically the only thing left to do, is
    // build the NSMapTable with the partData for the mime tree.
    __block NSMapTable *partData = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory valueOptions:NSPointerFunctionsStrongMemory capacity:0];
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

+ (NSData *)GMForceFetchMessageDataForMessage:(MCMessage *)message {
    return [message messageDataFetchIfNotAvailable:YES newDocumentID:nil];
}

+ (NSData *)GMRawDataForMessage:(MCMessage *)currentMessage topLevelPart:(MCMimePart *)topLevelPart fetchIfNotAvailable:(BOOL)fetchIfNotAvailable {
    // This method tries to load the complete message data from different sources.
    // 1.) Local .emlx file
    //     Mail caches the message data it fetches from the mail server in a local .emlx file
    //     In most cases however, only a partial.emlx file is available, which contains the message
    //     but the attachment data has been stripped out.
    //     Whenever there is a .emlx file with the complete message data available, GPGMail
    //     will always prefer and use that, since it's the most pure representation of the message
    //     as it is stored on the server.
    //
    // 2.) Local partial .emlx file with re-added attachment data
    //     If no local .emlx file is available, GPGMail tries to re-create the entire message data
    //     based on the mime tree of the partial .emlx file and the already downloaded attachment data.
    //     This approach is however not ideal when the message is PGP/MIME signed, since the re-created message
    //     data might differ from the data as stored on the server as Mail reformats headers in the partial.emlx file
    //
    // 3.) Original data from the server
    //     If approach nr. 2 fails, since not all attachments have been downloaded yet, or the message
    //     is PGP/MIME signed, GPGMail will attempt to force fetch the data from the server.
    BOOL isCompleteMessageAvailable = NO;
    NSData *messageData = [self GMMessageDataForMessage:currentMessage isCompleteMessageAvailable:&isCompleteMessageAvailable];
    if(isCompleteMessageAvailable) {
        return messageData;
    }
    
    if(!topLevelPart) {
        topLevelPart = [[MCMimePart alloc] initWithEncodedData:messageData];
        [topLevelPart parse];
    }
    BOOL mightContainPGPData = [(MimePart_GPGMail *)topLevelPart mightContainPGPMIMESignedData];
    // If the message is PGP/MIME signed but fetch is not allowed, no message data is returned.
    // The calling method might then release a lock and call this method again with fetchIfNotAvailable
    // enabled. Otherwise trying to fetch the data from the server might result in a deadlock.
    if(mightContainPGPData && !fetchIfNotAvailable) {
        return nil;
    }
    if(mightContainPGPData && fetchIfNotAvailable) {
        NSData *messageDataFromServer = [self GMForceFetchMessageDataForMessage:currentMessage];
        if(messageDataFromServer) {
            messageData = messageDataFromServer;
        }
        return messageData;
    }
    
    NSError *error = nil;
    NSData *localMessageData = [self GMLocalMessageDataForMessage:currentMessage topLevelPart:topLevelPart error:&error];
    if(!localMessageData && error) {
        if(fetchIfNotAvailable) {
            NSData *messageDataFromServer = [self GMForceFetchMessageDataForMessage:currentMessage];
            if(messageDataFromServer) {
                messageData = messageDataFromServer;
            }
            return messageData;
        }
        return nil;
    }
    
    messageData = localMessageData;
    return messageData;
}

+ (BOOL)GMGetTopLevelMimePart:(__autoreleasing id *)topLevelMimePart headers:(__autoreleasing id *)headers body:(__autoreleasing id *)body forMessage:(MCMessage *)currentMessage messageData:(NSData *)messageData shouldProcessPGPData:(BOOL)shouldProcessPGPData {
    // If for some reason no message data is available, something has gone terribly wrong.
    // Out of here!
    if(!messageData) {
        if(topLevelMimePart != NULL) {
            *topLevelMimePart = nil;
        }
        if(headers != NULL) {
            *headers = nil;
        }
        if(body != NULL) {
            *body = nil;
        }
        return NO;
    }
    
    // Create the mime part, headers and message body.
    NSRange headerDataRange = [messageData rangeOfRFC822HeaderData];
    NSData *headerData = [messageData subdataWithRange:headerDataRange];
    if(headers != NULL) {
        *headers = [[MCMessageHeaders alloc] initWithHeaderData:headerData encodingHint:0x0];
    }
    MCMimePart *mimePart = nil;
    if(topLevelMimePart != NULL || body != NULL) {
        NSData *bodyData = nil;
        if([messageData length] - (headerDataRange.location + headerDataRange.length) > 0) {
            NSRange bodyDataRange = NSMakeRange(headerDataRange.location + headerDataRange.length, [messageData length] - (headerDataRange.location + headerDataRange.length));
            bodyData = [messageData subdataWithRange:bodyDataRange];
        }
        mimePart = [[MCMimePart alloc] initWithEncodedHeaderData:headerData encodedBodyData:bodyData];
        if(![mimePart parse]) {
            mimePart = nil;
        }
        if(([currentMessage type] & 0xfe) == 0x6) {
            [mimePart setHideCalendarMimePart:YES];
        }
    }
    if(topLevelMimePart != NULL) {
        *topLevelMimePart = mimePart;
    }
    if(body != NULL && mimePart != NULL) {
        if(shouldProcessPGPData) {
            [mimePart setIvar:kMimePartAllowPGPProcessingKey value:@(YES)];
        }
        MCMessageBody *messageBody = [mimePart messageBody];
        // Set the security features collected on topLevelMimePart on the message.
        [currentMessage setIvar:kMessageSecurityFeaturesKey value:[(MimePart_GPGMail *)mimePart securityFeatures]];
        [self GMSetupDataSourcesForParsedMessage:messageBody ofMessage:currentMessage];
        *body = messageBody;
    }
    
    return YES;
}

+ (NSData *)GMMessageDataForMessage:(MCMessage *)currentMessage isCompleteMessageAvailable:(BOOL *)isCompleteMessageAvailable {
    NSData *messageData = nil;
    NSString *completeMessagePath = [MFLibrary _dataPathForMessage:currentMessage type:0];
    BOOL hasEntireMessage = [[NSFileManager defaultManager] fileExistsAtPath:completeMessagePath];
    *isCompleteMessageAvailable = hasEntireMessage;
    
    if(hasEntireMessage) {
        messageData = [MFLibrary _messageDataAtPath:completeMessagePath];
    }
    else {
        // The complete message is not available, so it's necessary to load the partial message in order to build
        // a mime tree from.
        messageData = [MFLibrary _messageDataAtPath:[MFLibrary _dataPathForMessage:currentMessage type:1]];
    }
    return messageData;
}

+ (BOOL)GMMessageMightContainPGPData:(MCMessage *)message {
    BOOL isCompleteMessageAvailable = NO;
    NSData *messageData = [self GMMessageDataForMessage:message isCompleteMessageAvailable:&isCompleteMessageAvailable];
    MCMimePart *topLevelMimePart = [[MCMimePart alloc] initWithEncodedData:messageData];
    if([topLevelMimePart parse] && [(MimePart_GPGMail *)topLevelMimePart mightContainPGPData]) {
        return YES;
    }
    
    return NO;
}

+ (BOOL)MAGetTopLevelMimePart:(__autoreleasing id *)topLevelMimePart headers:(__autoreleasing id *)headers body:(__autoreleasing id *)body forMessage:(MCMessage *)currentMessage {
    // This method is responsible for fetching the complete message data
    // in case it's not yet available, or re-construct it from the locally cached data.
    // It's only allowed to do so however, if a user actively selected a message, in which
    // case it's invoked from -[RedundantContentIdentificationManager redundantContentMarkupForMessage:inConversation:]
    // and the current thread dictionary has the ReturnCompleteBodyData and the ReturnCompleteBodyDataForMessage message reference set.
    BOOL wantsCompleteBodyData = ([[[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataKey] boolValue] &&
                                  [[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataForMessageKey] == currentMessage) || [[[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataForComposeBackendKey] boolValue];
    
    BOOL isCompleteMessageAvailable = NO;
    NSData *messageData = [self GMMessageDataForMessage:currentMessage isCompleteMessageAvailable:&isCompleteMessageAvailable];
    
    return [self GMGetTopLevelMimePart:topLevelMimePart headers:headers body:body forMessage:currentMessage messageData:messageData shouldProcessPGPData:wantsCompleteBodyData];
}

+ (void)GMSetupDataSourcesForParsedMessage:(id)parsedMessage ofMessage:(MCMessage *)message {
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
}

+ (void)MASetData:(id)data forMessage:(id)message isPartial:(BOOL)isPartial hasCompleteText:(BOOL)hasCompleteText {
    // Since 10.12.4 it seems possible to force Mail to fetch the entire message body again for multipart/signed messages,
    // by returning NO from -[MFLibraryMessage shouldSnipAttachmentData].
    // In -[MFLibraryMessage shouldSnipAttachmentData] the data is however not available, which is the reason
    // why it's necessary to instruct -[MFLibraryMessage shouldSnipAttachmentData] to return NO, if a multipart/signed message
    // was found by setting an ivar on the message itself.
    MCMimePart *mimePart = [[MCMimePart alloc] initWithEncodedData:data];
    [mimePart parse];
    // Check if the message contains a PGP/MIME signature.
    BOOL mightContainPGPData = [(MimePart_GPGMail *)mimePart mightContainPGPMIMESignedData];
    if(mightContainPGPData) {
        [message setIvar:kLibraryMessagePreventSnippingAttachmentDataKey value:@(YES)];
    }
    [self MASetData:data forMessage:message isPartial:isPartial hasCompleteText:hasCompleteText];
}

@end
