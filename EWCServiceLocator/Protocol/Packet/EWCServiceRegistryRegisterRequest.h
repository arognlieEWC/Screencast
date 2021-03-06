//
//  EWCServiceRegistryRegisterRequest.h
//  Screencast
//
//  Created by Ansel Rognlie on 2018/02/06.
//  Copyright © 2018 Ansel Rognlie. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "EWCServiceRegistryPacket.h"

@class EWCServiceRegistryProtocol;
@class EWCAddressIpv4;

@interface EWCServiceRegistryRegisterRequest : NSObject<EWCServiceRegistryPacket>

+ (void)registerPacket:(EWCServiceRegistryProtocol *)protocol;
+ (void)unregisterPacket:(EWCServiceRegistryProtocol *)protocol;

// client use
+ (instancetype)packetWithServiceId:(NSUUID *)serviceId
                       providerName:(NSString *)providerName
                               port:(uint16_t)port;

// server use
+ (instancetype)packetWithServiceId:(NSUUID *)serviceId
                       providerName:(NSString *)providerName
                            address:(EWCAddressIpv4 *)address;

// client use
- (instancetype)initWithServiceId:(NSUUID *)serviceId
                     providerName:(NSString *)providerName
                             port:(uint16_t)port;

// server
- (instancetype)initWithServiceId:(NSUUID *)serviceId
                     providerName:(NSString *)providerName
                          address:(EWCAddressIpv4 *)address;

@property NSUUID *serviceId;
@property EWCAddressIpv4 *address;
@property NSString *providerName;

- (NSData *)getData;

@end
