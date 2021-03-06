//
//  EWCServiceRegistryQueryRequest.h
//  Screencast
//
//  Created by Ansel Rognlie on 2018/02/12.
//  Copyright © 2018 Ansel Rognlie. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "EWCServiceRegistryPacket.h"

@class EWCServiceRegistryProtocol;

@interface EWCServiceRegistryQueryRequest : NSObject<EWCServiceRegistryPacket>

+ (void)registerPacket:(EWCServiceRegistryProtocol *)protocol;
+ (void)unregisterPacket:(EWCServiceRegistryProtocol *)protocol;

// client use
+ (instancetype)packetWithServiceId:(NSUUID *)serviceId;

// client use
- (instancetype)initWithServiceId:(NSUUID *)serviceId;

@property NSUUID *serviceId;

- (NSData *)getData;

@end
