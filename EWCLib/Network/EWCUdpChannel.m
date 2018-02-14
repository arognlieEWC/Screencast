//
//  EWCUdpChannel.m
//  Screencast
//
//  Created by Ansel Rognlie on 2018/01/30.
//  Copyright © 2018 Ansel Rognlie. All rights reserved.
//

#import "EWCUdpChannel.h"
#import "EWCUdpChannel+EWCUdpChannelProtected.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import "EWCBufferedPacket.h"
#import "../CoreFoundation/EWCCFTypeRef.h"

static void HandleSocketCallback(CFSocketRef s,
                                 CFSocketCallBackType type,
                                 CFDataRef address,
                                 const void *data,
                                 void *info);

@interface EWCUdpChannel()
@property NSRunLoop *runLoop;
@property (nonatomic) CFSocketRef localSocket;
@property (nonatomic) CFRunLoopSourceRef socketSource;
@property NSMutableArray<EWCBufferedPacket *> *transmitBuffer;
@property (readonly) uint16_t listenerPort;
@property (readonly) BOOL enableBroadcast;
@end

@implementation EWCUdpChannel {
    BOOL canWrite_;
    struct sockaddr_in boundAddr_;
}

// initializer /////////////////////////////////////////////////

- (instancetype)init {
    self = [super init];
    
    _localSocket = nil;
    _socketSource = nil;
    _runLoop = nil;
    canWrite_ = NO;
    self.transmitBuffer = [NSMutableArray<EWCBufferedPacket *> array];

    memset(&boundAddr_, 0, sizeof(boundAddr_));
    
    return self;
}

- (void)dealloc {
    self.localSocket = nil;
    self.socketSource = nil;
    self.runLoop = nil;
    self.transmitBuffer = nil;
}

// public entry points ////////////////////////////////////////////////

- (void)start {
    [self startOnRunLoop:[NSRunLoop currentRunLoop]];
}

- (void)startOnRunLoop:(NSRunLoop *)runLoop {
    // note the run loop
    self.runLoop = runLoop;
    
    [self startSocket];
}

- (void)stop {
    [self stopSocket];
}

- (void)getBoundAddress:(struct sockaddr *)address length:(socklen_t *)length {
    // make sure the passed in addr has at least the length required for
    // a sockaddr_in

    if (*length < sizeof(boundAddr_)) { return; }

    // update out params
    *length = sizeof(boundAddr_);
    *(struct sockaddr_in *)address = boundAddr_;
}

// private methods ///////////////////////////////////////////////////////

- (void)startSocket {
    NSLog(@"starting socket...");
    
    int newSocket = [self prepareSocket];
    if (! newSocket) {
        return;
    }
    
    // initialize a context to hold our self reference for event handling
    CFSocketContext ctx = {0, (__bridge void *)(self), NULL, NULL, NULL};
    
    // get a core foundation socket with our callback handler
    CFSocketRef sock = CFSocketCreateWithNative(kCFAllocatorDefault,
                                                newSocket,
                                                kCFSocketDataCallBack | kCFSocketWriteCallBack,
                                                &HandleSocketCallback,
                                                &ctx);
    self.localSocket = sock;
    CFRelease(sock);
    
    // set option to free the socket once it is invalidated
    CFOptionFlags flags = CFSocketGetSocketFlags(sock);
    flags |= kCFSocketCloseOnInvalidate;
    CFSocketSetSocketFlags(sock, flags);
    
    // create a run loop source for the socket to get notified of events
    CFRunLoopSourceRef socksrc = CFSocketCreateRunLoopSource(kCFAllocatorDefault, sock, 0);
    self.socketSource = socksrc;
    CFRelease(socksrc);
    
    // add the source to the run loop
    CFRunLoopAddSource([self.runLoop getCFRunLoop], socksrc, kCFRunLoopDefaultMode);
    
    NSLog(@"listening...");
}

- (void)stopSocket {
    NSLog(@"shutting down...");
    
    // invalidate (and free) listening socket
    if (self.localSocket) {
        CFSocketInvalidate(self.localSocket);
        self.localSocket = nil;
    }
    
    // remove and release the run loop source
    if (self.socketSource) {
        CFRunLoopRemoveSource([self.runLoop getCFRunLoop],
                              self.socketSource,
                              kCFRunLoopDefaultMode);
        self.socketSource = nil;
    }
    
    NSLog(@"stopped.");
}

- (void)setLocalSocket:(CFSocketRef)value {
    EWCSwapCFTypeRef(&_localSocket, &value);
}

- (void)setSocketSource:(CFRunLoopSourceRef)value {
    EWCSwapCFTypeRef(&_socketSource, &value);
}

- (int)prepareSocket {
    // make sure the listener port has been overridden
    uint16_t port = self.listenerPort;
    
    int localSocket = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (localSocket <= 0) {
        return 0;
    }
    
    if (self.enableBroadcast) {
        int enable = 1;
        int error = setsockopt(localSocket,
                               SOL_SOCKET,
                               SO_BROADCAST,
                               (void *)&enable,
                               sizeof(enable));
        if (error) { return 0; }
    }
    
    struct sockaddr_in sockaddr;
    memset(&sockaddr, 0, sizeof(sockaddr));
    sockaddr.sin_len = sizeof(sockaddr);
    sockaddr.sin_family = AF_INET;
    sockaddr.sin_port = htons(port);
    sockaddr.sin_addr.s_addr = htonl(INADDR_ANY);
    
    int status = bind(localSocket, (struct sockaddr *)&sockaddr, sizeof(sockaddr));
    if (status == -1) {
        close(localSocket);
        return 0;
    }

    // get the actual bound addr
    socklen_t socklen = sizeof(boundAddr_);
    status = getsockname(localSocket, (struct sockaddr *)&boundAddr_, &socklen);

    return localSocket;
}

-(void)handleCallbackWithSocket:(CFSocketRef)s
                   callbackType:(CFSocketCallBackType)type
                        address:(CFDataRef)addr
                           data:(const void *)data {
    // process the socket event
    if (type == kCFSocketDataCallBack) {
        NSLog(@"received packet.");
        
        // who connected
        struct sockaddr_in remoteSocket;
        uint8 *octet;
        if (CFDataGetLength(addr) != sizeof(remoteSocket)) {
            return;
        }
        CFDataGetBytes(addr, CFRangeMake(0, sizeof(remoteSocket)), (UInt8 *)&remoteSocket);
        in_addr_t ipaddr = ntohl(remoteSocket.sin_addr.s_addr);
        octet = (uint8 *)&ipaddr;
        NSLog(@"remote addr: %d.%d.%d.%d:%d", octet[3], octet[2], octet[1], octet[0],
              ntohs(remoteSocket.sin_port));
        
        // what was sent
        CFDataRef dataRef = (CFDataRef)data;
        NSData *bytes = (__bridge_transfer NSData *)CFDataCreateCopy(kCFAllocatorDefault, dataRef);

        EWCAddressIpv4 *address = [EWCAddressIpv4 addressWithAddress:&remoteSocket];

        // notify overridden handler
        [self handlePacketData:bytes fromAddress:address];
    } else if (type == kCFSocketWriteCallBack) {
        canWrite_ = YES;
        
        [self sendBufferedData];
    }
}

- (void)sendBufferedData {
    // if no data, or unable to send, just exit for now
    if (! canWrite_ || ! self.transmitBuffer.count) { return; }
    
    EWCBufferedPacket *packet = self.transmitBuffer.firstObject;
    
    CFSocketError error;
    error = CFSocketSendData(self.localSocket, packet.address, packet.data, 0);
    
    if (error == kCFSocketSuccess) {
        // remove the data so that it isn't sent again
        [self.transmitBuffer removeObjectAtIndex:0];
    } else {
        // mark that we're not ready to send
        canWrite_ = NO;
    }
}

- (void)sendPacketData:(NSData *)data toAddress:(EWCAddressIpv4 *)address {
    // populate the subsystem format address
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(struct sockaddr_in));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(address.port);
    addr.sin_addr.s_addr = htonl(address.addressIpv4);

    // wrap the data and address for transmission
    CFDataRef dataRef = (__bridge_retained CFDataRef)[data copy];
    CFDataRef addrRef = CFDataCreate(kCFAllocatorDefault, (UInt8 *)&addr, sizeof(addr));
    
    // buffer the data until we're allowed to send
    [self.transmitBuffer addObject:[EWCBufferedPacket packetWithData:dataRef address:addrRef]];
    
    CFRelease(dataRef);
    CFRelease(addrRef);
    
    // attempt to send buffered data
    [self sendBufferedData];
}

- (void)broadcastPacketData:(NSData *)data port:(uint16_t)port {
    // do nothing if we aren't enabled for broadcast
    if (! self.enableBroadcast) { return; }

    EWCAddressIpv4 *address = [EWCAddressIpv4 addressWithAddressIpv4:INADDR_BROADCAST
                                                                port:port];

    [self sendPacketData:data toAddress:address];
}

// protected overrides //////////////////////////////////////////////

- (uint16_t)listenerPort {
    NSLog(@"subclass must override (uint16_t)getListeningPort");
    return 0;
}

- (void)handlePacketData:(NSData *)data fromAddress:(EWCAddressIpv4 *)address {
    NSLog(@"subclass must override (void)handlePacketData:fromAddress:");
}

- (BOOL)enableBroadcast {
    // does not require override if no broadcast required
    return NO;
}

@end

// static entry points //////////////////////////////////////////////

static void HandleSocketCallback(CFSocketRef s,
                                 CFSocketCallBackType type,
                                 CFDataRef address,
                                 const void *data,
                                 void *info) {
    EWCUdpChannel *listener = (__bridge EWCUdpChannel *)(info);
    [listener handleCallbackWithSocket:s callbackType:type address:address data:data];
}