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

#define MAIL_SELF(self) ((MFLibrary *)(self))

extern NSString *MCDescriptionForMessageFlags(int arg0);
extern const NSString *kMimeBodyMessageKey;

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

+ (NSData *)GMDataForMessage:(MCMessage *)message mimePart:(MCMimePart *)mimePart {
    MCAttachment *attachment = [[MCAttachment alloc] initWithMimePart:mimePart];
    MFLibraryAttachmentDataSource *dataSource = [[MFLibraryAttachmentDataSource alloc] initWithMessage:message mimePartNumber:[mimePart partNumber] attachment:attachment remoteDataSource:nil];
    
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
            partBodyData = [[self class] GMDataForMessage:message mimePart:mimePart];
            if(!partBodyData) {
                // If the data of an attachment is missing, abort. This means that the attachment
                // or for now the entire message has to be re-fetched.
                partError = [NSError errorWithDomain:@"GMAttachmentMissingError" code:201000 userInfo:nil];
                return;
            }
            if([mimePart.contentTransferEncoding isEqualToString:@"base64"]) {
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
    BOOL isMCLibraryMessage = [currentMessage isKindOfClass:[MFLibraryMessage class]];
    BOOL userDidSelectMessage = [[currentMessage getIvar:@"UserSelectedMessage"] boolValue];
    BOOL isCompleteMessageDataAvailable = [MFLibrary _messageDataAtPath:[MFLibrary _dataPathForMessage:currentMessage type:0]] != nil;
    BOOL isFullMessageDataAvailableAfterFetching = [currentMessage ivarExists:@"FullBodyDataAvailable"] && [currentMessage getIvar:@"FullBodyData"] != nil;
    BOOL isFetchingMessageData = [currentMessage ivarExists:@"BodyFetchingInProgress"];
    
    // Let Mail generate the mime body from the partial emlx file.
    // Even if only the partial emlx is available, it will be necessary to re-create the message from attachments.
    MCMimeBody *mimeBody = [self MAMimeBodyForMessage:currentMessage];
    if(!isMCLibraryMessage || !userDidSelectMessage || isCompleteMessageDataAvailable || isFetchingMessageData) {
        if(userDidSelectMessage) {
            [mimeBody setIvar:kMimeBodyMessageKey value:currentMessage];
        }
        return mimeBody;
    }
    
    NSError *error = nil;
    // 1.) Check if cached data is available.
    NSData *messageData = [currentMessage getIvar:@"FullBodyData"];
    if(!messageData) {
        [currentMessage setIvar:@"BodyFetchingInProgress" value:@(YES)];
        [currentMessage setIvar:@"FakeContentNotAvailable" value:@YES];
        // 2.) Check if message data can be re-created from already downloaded attachments.
        messageData = [self localMessageDataForMessage:currentMessage mimeBody:mimeBody error:&error];
        if(!messageData && error) {
            // 3.) Building message data from downloaded attachments failed, now fetch the data from the server.
            messageData = [self forceFetchMessageDataForMessage:currentMessage];
        }
        [currentMessage removeIvar:@"BodyFetchingInProgress"];
        [currentMessage setIvar:@"FullBodyDataAvailable" value:@YES];
        [currentMessage setIvar:@"FullBodyData" value:messageData];
    }
    else {
        DebugLog(@"Full body data already available: %lu", (unsigned long)[messageData length]);
    }
    
    if(!messageData) {
        [mimeBody setIvar:kMimeBodyMessageKey value:currentMessage];
        return mimeBody;
    }
    
    NSLog(@"Fetched data: %lu", (unsigned long)[messageData length]);
    MCMimePart *mimePart = [[MCMimePart alloc] initWithEncodedData:messageData];
    mimeBody = [MCMimeBody new];
    [mimeBody setTopLevelPart:mimePart];
    [mimePart setMimeBody:mimeBody];
    [mimePart parse];
    [mimeBody setIvar:kMimeBodyMessageKey value:currentMessage];
    return mimeBody;
}

+ (id)MAParsedMessageForMessage:(id)message {
    MCMimeBody *mimeBody = [[MAIL_SELF(self) class] mimeBodyForMessage:message];
    if(!mimeBody) {
        return [self MAParsedMessageForMessage:message];
    }
    
    // Check if there's a decrypted mimeBody on the mimeBody.
    MCMimeBody *decryptedMimeBody = [[mimeBody topLevelPart] decryptedMimeBodyIsEncrypted:NULL isSigned:NULL error:nil];
    if(!decryptedMimeBody) {
        // Make sure the message is decoded.
        id parsedMessage = [mimeBody parsedMessage];
        // TODO: Might need some error checking so we don't repeatedly try to get a decrypted mime body, even though decryption fails.
        decryptedMimeBody = [[mimeBody topLevelPart] decryptedMimeBodyIsEncrypted:NULL isSigned:NULL error:nil];
    }
    
    if(decryptedMimeBody) {
        return [decryptedMimeBody parsedMessage];
    }
    
    return [self MAParsedMessageForMessage:message];
}

+ (BOOL)MAIsMessageContentLocallyAvailable:(id)arg1 {
    BOOL ret = [self MAIsMessageContentLocallyAvailable:arg1];
    if([[arg1 getIvar:@"FakeContentNotAvailable"] boolValue]) {
        [arg1 removeIvar:@"FakeContentNotAvailable"];
        return NO;
    }
    return ret;
}

@end
