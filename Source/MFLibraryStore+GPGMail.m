/* MFLibraryStore+GPGMail.m created by Lukas Pitschl (@lukele) on Thursday 21-Sep-2017 */

/*
 * Copyright (c) 2017, GPGTools <team@gpgtools.org>
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
 * THIS SOFTWARE IS PROVIDED BY GPGTools ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL GPGTools BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */
#import "MFLibraryStore+GPGMail.h"

#import "NSObject+LPDynamicIvars.h"

#import "MCMessage.h"
#import "Library+GPGMail.h"
#import "MFLibraryStore.h"
#import "MCMessageBody.h"
#import "MFLibrary.h"

extern NSString * const kLibraryMimeBodyReturnCompleteBodyDataForComposeBackendKey;
extern NSString * const kLibraryMimeBodyReturnCompleteBodyDataForMessageKey;
extern NSString * const kLibraryMimeBodyReturnCompleteBodyDataKey;

NSString * const kMFLibraryStoreMessageBodyContainsPGPData = @"MFLibraryStoreMessageBodyContainsPGPData";
NSString * const kMFLibraryStoreMessageDataFetchLockMap = @"MFLibraryStoreMessageDataFetchLockMap";

// This class is responsible for fetching message data on High Sierra.

@implementation MFLibraryStore_GPGMail

- (void)MAGetTopLevelMimePart:(id *)topLevelMimePart headers:(id *)headers body:(id *)body forMessage:(MCMessage *)currentMessage fetchIfNotAvailable:(BOOL)fetchIfNotAvailable updateFlags:(BOOL)updateFlags allowPartial:(BOOL)allowPartial {
    // In macOS High Sierra, Mail has introduced a new caching technique, in order to cache
    // headers, body and mime structure in memory.
    // When a message is first fetched from a mail server, the mime tree is parsed and a representing html body
    // is created, which is then cached for every further display until a user restarts Mail.
    // While this is a very welcome change for normal messages, since it speeds message loading
    // up immensely, it's not suitable for PGP messages.
    // If GPGMail tries to handle PGP data in messages when their mime tree is first parsed, users would be
    // bothered by passphrase requests even though they might not be viewing the message at the time and might
    // not be interested in its content at the time. In addition, if they were to cancel the passphrase request,
    // the body would be cached in encrypted manner and would never be decrypted again, unless the user restarts
    // Mail.
    // In order to fix this usability nuisance, GPGMail tries to figure out if a message contains PGP data
    // and if it does, will disable the caching mechanism for that particular message.
    // Since the complete body data is no longer available in most cases, a best guess has to be performed
    // based on the mime structure of a message.
    
    // Since macOS Sierra, the body data of a message is stripped of data belonging to individual attachments.
    // This information is however highly necessary in order to correctly detect and process PGP data when the mime
    // structure is parsed internally to prepare the message for display.
    // In order to fix that, the wantsCompleteBodyData signals if a user actively selected a message, and in that
    // case, GPGMail will try to re-construct the entire body data (including attachment data) by either injecting
    // the attachment data from already downloaded attachments, or by re-downloading the complete message.
    BOOL wantsCompleteBodyData = ([[[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataKey] boolValue] &&
                                  [[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataForMessageKey] == currentMessage) || [[[[NSThread currentThread] threadDictionary] valueForKey:kLibraryMimeBodyReturnCompleteBodyDataForComposeBackendKey] boolValue];
    // If either wantsCompleteBodyData is not set, or body is NULL, so the Mail call is not interested in
    // the message body data, call the original Mail method.
    if(!wantsCompleteBodyData || body == NULL) {
        return [self MAGetTopLevelMimePart:topLevelMimePart headers:headers body:body forMessage:currentMessage fetchIfNotAvailable:fetchIfNotAvailable updateFlags:updateFlags allowPartial:allowPartial];
    }
    // If a message body is cached and it is not flagged as containing PGP data, the cached version is returned.
    MCMessageBody *cachedMessageBody = [(MFLibraryStore *)self _cachedBodyForMessage:currentMessage valueIfNotPresent:NULL];
    if([cachedMessageBody ivarExists:kMFLibraryStoreMessageBodyContainsPGPData] && [[cachedMessageBody getIvar:kMFLibraryStoreMessageBodyContainsPGPData] boolValue] == NO) {
        return [self MAGetTopLevelMimePart:topLevelMimePart headers:headers body:body forMessage:currentMessage fetchIfNotAvailable:fetchIfNotAvailable updateFlags:updateFlags allowPartial:allowPartial];
    }
    
    // Now all the best cases are covered, down to the nitty gritty.
    NSMutableDictionary *messageLockMap = [self valueForKey:@"_libraryFetchLockMap"];
    NSRecursiveLock *messageLock = nil;
    @synchronized(messageLockMap) {
        messageLock = messageLockMap[currentMessage];
        if(!messageLock) {
            messageLock = [NSRecursiveLock new];
            messageLockMap[currentMessage] = messageLock;
        }
    }
    [messageLock lock];
    
    if(![Library_GPGMail GMMessageMightContainPGPData:currentMessage]) {
        // If the message doesn't contain any PGP data, call the original Mail method.
        [messageLock unlock];
        messageLockMap = [self valueForKey:@"_libraryFetchLockMap"];
        @synchronized(messageLockMap) {
            NSRecursiveLock *endLock = messageLockMap[currentMessage];
            if(messageLock == endLock) {
                @try {
                    [messageLockMap removeObjectForKey:currentMessage];
                }
                @catch(NSException *exception) {
                    @throw exception;
                    // Should we do something here? Maybe fall back?
                }
            }
        }
        [self MAGetTopLevelMimePart:topLevelMimePart headers:headers body:body forMessage:currentMessage fetchIfNotAvailable:fetchIfNotAvailable updateFlags:updateFlags allowPartial:allowPartial];
        return;
    }
    
    // The message contains PGP data, so the first step is to try to re-create the complete body data
    // from locally available message data. If the message hasn't been downloaded yet in its entirety,
    // the message data is fetched from the mail server.
    // By passing nil as topLevelPart, -[MFLibrary GMRawDataForMessage:topLevelPart:fetchIfNotAvailable] will
    // create one based on the always available partial message.
    NSData *messageData = [Library_GPGMail GMRawDataForMessage:currentMessage topLevelPart:nil fetchIfNotAvailable:NO];
    if(!messageData) {
        // Now it's necessary to fetch the message data from the server.
        // In order to avoid a deadlock, since -[MFLibrary forceFetchMessageDataForMessage:] calls into this method
        // the lock from the libraryFetchLockMap is released, and a different one is used, in order to prevent
        // multiple calls to this method to fetch the data at the same time.
        NSMutableDictionary *messageDataFetchLockMap = [self getIvar:kMFLibraryStoreMessageDataFetchLockMap];
        if(!messageDataFetchLockMap) {
            messageDataFetchLockMap = [NSMutableDictionary new];
            [self setIvar:kMFLibraryStoreMessageDataFetchLockMap value:messageDataFetchLockMap];
        }
        NSLock *messageDataFetchLock = nil;
        @synchronized(messageDataFetchLockMap) {
            messageDataFetchLock = messageDataFetchLockMap[currentMessage];
            if(!messageDataFetchLock) {
                messageDataFetchLock = [NSLock new];
                messageDataFetchLockMap[currentMessage] = messageDataFetchLock;
            }
        }
        [messageLock unlock];
        
        [messageDataFetchLock lock];
        @try {
            messageData = [Library_GPGMail GMRawDataForMessage:currentMessage topLevelPart:nil fetchIfNotAvailable:YES];
        }
        @catch(NSException *exception) {
            @throw exception;
        }
        @finally {
            [messageDataFetchLock unlock];
            messageDataFetchLockMap = [self getIvar:kMFLibraryStoreMessageDataFetchLockMap];
            @synchronized(messageDataFetchLockMap) {
                NSLock *endLock = messageDataFetchLockMap[currentMessage];
                if(messageDataFetchLock == endLock) {
                    @try {
                        [messageDataFetchLockMap removeObjectForKey:currentMessage];
                    }
                    @catch(NSException *exception) {
                        @throw exception;
                        // Should we do something here? Maybe fall back?
                    }
                }
            }
        }
    }
    
    @try {
        BOOL success = [Library_GPGMail GMGetTopLevelMimePart:topLevelMimePart headers:headers body:body forMessage:currentMessage messageData:messageData shouldProcessPGPData:YES];
    }
    @catch (NSException *exception) {
        // As a fallback, invoke the original method.
        @throw exception;
        [self MAGetTopLevelMimePart:topLevelMimePart headers:headers body:body forMessage:currentMessage fetchIfNotAvailable:fetchIfNotAvailable updateFlags:updateFlags allowPartial:allowPartial];
    }
    @finally {
        [messageLock unlock];
    }
    
    messageLockMap = [self valueForKey:@"_libraryFetchLockMap"];
    @synchronized(messageLockMap) {
        NSRecursiveLock *endLock = messageLockMap[currentMessage];
        if(messageLock == endLock) {
            @try {
                [messageLockMap removeObjectForKey:currentMessage];
            }
            @catch(NSException *exception) {
                @throw exception;
                // Should we do something here? Maybe fall back?
            }
        }
    }
}

@end

