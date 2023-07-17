//
//  WDBLEPeripheral.m
//  
//
//  Created by summer on 2023/6/14.
//

#import "WDBLEPeripheral.h"

@implementation WDBLEPeripheral
- (instancetype)init
{
	if (self = [super init]) {
		self.m_peripheralIdentifier = @"";
		self.m_peripheralLocaName   = @"";
		self.m_peripheralName       = @"";
		self.m_peripheralUUID       = @"";
		self.m_peripheralRSSI       = [[NSNumber alloc]init];
		self.m_peripheralIsBind     = false;
	}
	return self;
}




@end

static CurPeripheral *peripheral = nil;
@implementation CurPeripheral

+ (instancetype)shareInstance
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		peripheral = [[CurPeripheral alloc]init];
	});
	return peripheral;
}


@end
