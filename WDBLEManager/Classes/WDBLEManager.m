//
//  XJKBLEManager.m
//
//  Created by summer on 2023/6/14.
//

#import <UIKit/UIKit.h>
#import "WDBLEManager.h"

typedef BOOL (^FilterPeripheral)(NSString *peripheralName, NSDictionary *advertisementData, NSNumber *rssi);
typedef void (^DidDiscoverPeripheral) (CBPeripheral *m_peripheral,NSDictionary* advertisementDict,NSNumber *rssi);
typedef void (^DidConnectPeripheral) (BOOL isConnect);
typedef void (^DidDisConnectedPeripheral) (CBPeripheral *peripheral);
typedef void (^DidPeripheralUpdateValue)(CBPeripheral *peripheral,CBCharacteristic *curCharacteristic);
typedef void (^ReadRSSI)(CBPeripheral *peripheral,NSNumber *rssi);
typedef void (^WriteforCharacteristic)(CBPeripheral *peripheral,CBCharacteristic *TXCharacteristic);
typedef void (^WriteOutforCharacteristic)(CBPeripheral *peripheral,CBCharacteristic *TXOutCharacteristic);
typedef void (^DidWriteValueSuccess)(CBPeripheral *peripheral,CBCharacteristic *curCharacteristic,NSError *error);
typedef void (^DidDiscoverPeripheral) (CBPeripheral *m_peripheral,NSDictionary* advertisementDict,NSNumber *rssi);
typedef void (^getServices)(NSArray *ary,NSError *error);
typedef void (^getCharacteristics)(NSArray *notifys,NSArray *writes,NSArray *outwrites,NSArray *reads,NSError *error);
typedef void (^getBluetoothState) (BLECentralManagerState state);

static double SCAN_TIMER          = 2.0;    //!<扫描频率
static WDBLEManager *xjkBLEManager = nil;

@interface WDBLEManager()<CBCentralManagerDelegate,CBPeripheralDelegate>
@property(nonatomic, copy) FilterPeripheral filterPeripheralBlock;
@property(nonatomic, copy) DidDiscoverPeripheral discoverBlock;
@property(nonatomic, copy) DidConnectPeripheral connectBlock;
@property(nonatomic, copy) DidDisConnectedPeripheral connectedBlock;
@property(nonatomic, copy) DidPeripheralUpdateValue valueBlock;
@property(nonatomic, copy) WriteforCharacteristic txCharacteristic;
@property(nonatomic, copy) WriteOutforCharacteristic txOutCharacteristic;
@property(nonatomic, copy) DidWriteValueSuccess writeSuccess;
@property(nonatomic, copy) ReadRSSI readRSSIBlock;
@property(nonatomic, copy) getServices getServicesBlock;
@property(nonatomic, copy) getCharacteristics getCharacteristicsBlock;
@property(nonatomic, copy) getBluetoothState bluetoothStateBlock;
@property(nonatomic, assign) BLECentralManagerState  bleState;
@property(nonatomic, strong) NSString *m_peripheralName;///<连接上的设备名称
@property(nonatomic, strong) WDBLEPeripheral *l_per;
@property(nonatomic, strong) NSTimer *stateTimer;
@property(nonatomic, strong) NSTimer *scanTimer;                  ///< 循环扫描
@property(nonatomic, strong) NSArray *tempServices;
@property(nonatomic, strong) CBCharacteristic *m_TXCharacteristic;
@property(nonatomic, strong) CBCharacteristic *m_TXOutCharacteristic;
@property(nonatomic, strong) CBCharacteristic *m_RXCharacteristic;
@property(nonatomic, strong) CBCharacteristic *m_NotifyCharacteristic;///<通知的特征值
@property(nonatomic, strong) NSLock *scanLock;
@property(nonatomic, strong) NSMutableArray *uuidAry;
@property(nonatomic, strong) dispatch_source_t backgroundTimer;
@property(nonatomic, assign) BOOL isBackground;               ///<停止蓝牙连接
@property(nonatomic, assign) NSInteger backgroundCount;
@property(nonatomic, strong) dispatch_semaphore_t backgroundLock;
@property(nonatomic, assign)NSUInteger m_peripheralMTU; ///<连接的设备MTU
@property(nonatomic, copy) NSArray *m_NotifyCharacteristicAry;
@property(nonatomic, strong) NSMutableDictionary *tmpDictionary;
@property(nonatomic,strong)NSArray *services;

@end
@implementation WDBLEManager

#pragma mark -- 懒加载 --
- (NSMutableDictionary *)tmpDictionary{
    if (!_tmpDictionary) {
        _tmpDictionary = [NSMutableDictionary dictionary];
    }
    return _tmpDictionary;
}
- (NSMutableArray *)m_array_peripheral
{
    if (!_m_array_peripheral) {
        _m_array_peripheral = [NSMutableArray array];
    }
    return _m_array_peripheral;
}

- (WDBLEManager * _Nonnull (^)(double))setTimeInterval
{
	return ^id(double time){
		if (time > 0) {
			SCAN_TIMER = time;
		} else {
			[NSException raise:@"error parameter" format:@"timeInterval id can not = %f",time];
		}
		return [WDBLEManager shareInstance];
	};
}

- (WDBLEManager * _Nonnull (^)(NSArray<CBUUID *> * _Nonnull))setServices
{
	__weak typeof(self) weakSelf = self;
	return ^id(NSArray *services){
		__strong typeof((weakSelf)) strongSelf = (weakSelf);
		if (services.count>0) {
			strongSelf.tempServices = services;
			[strongSelf.uuidAry addObjectsFromArray:services];
		}
		return [WDBLEManager shareInstance];
	};
}


+ (instancetype)shareInstance
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		xjkBLEManager = [[WDBLEManager alloc]init];
	});
	return xjkBLEManager;
}

- (instancetype)init
{
	if (self = [super init]) {
		self.m_manger = [[CBCentralManager alloc]init];
		self.m_manger.delegate = self;
		self.scanLock = [[NSLock alloc] init];
		self.backgroundLock = dispatch_semaphore_create(1);
		//UIApplicationDidEnterBackgroundNotification
		[[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(appDidBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
		[[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
	}
	return self;
}

- (void)appDidBackground
{
    self.isBackground = true;
    /*
    app后台运行时必须扫描指定的特征值
     */
	if (self.tempServices.count>0) {
		self.uuidAry = [NSMutableArray arrayWithArray:self.tempServices];
	}
}
- (void)appWillEnterForeground
{
    dispatch_semaphore_wait(self.backgroundLock, DISPATCH_TIME_FOREVER);
    self.isBackground = false;
    self.uuidAry = nil;
    dispatch_semaphore_signal(self.backgroundLock);
}


//扫描蓝牙外设å
- (void)scanfunction
{
	__weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		__strong typeof((weakSelf)) strongSelf = (weakSelf);
        [strongSelf.m_manger scanForPeripheralsWithServices:self.uuidAry options:nil];
    });
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    switch (central.state) {
        case CBManagerStateUnknown:
        {
            [self.scanTimer invalidate];
            self.bleState = unknown;
            if (self.bluetoothStateBlock != nil) {
                self.bluetoothStateBlock(unknown);
            }
            break;
        }
        case CBManagerStateUnsupported:{
            [self.scanTimer invalidate];
            self.bleState = unknown;
            if (self.bluetoothStateBlock != nil) {
                self.bluetoothStateBlock(unknown);
            }
            NSLog(@"设备不支持蓝牙!");
            break;
        }
        case CBManagerStatePoweredOn:
        {
            // 开启定时器
            [self.scanTimer setFireDate:[NSDate distantPast]];
            self.scanTimer = [NSTimer scheduledTimerWithTimeInterval:SCAN_TIMER target:self selector:@selector(scanfunction) userInfo:nil repeats:YES];
            [[NSRunLoop mainRunLoop]addTimer:self.scanTimer forMode:NSRunLoopCommonModes];
            self.bleState = poweredOn;
            if (self.bluetoothStateBlock != nil) {
                self.bluetoothStateBlock(poweredOn);
            }
            break;
        }
        case CBManagerStatePoweredOff:
        {
            [self.scanTimer invalidate];
            self.bleState = poweredOff;
            if (self.bluetoothStateBlock != nil) {
                self.bluetoothStateBlock(poweredOff);
            }
            NSLog(@"=========蓝牙关闭");
            break;
        }
        default:
            break;
    }
    
}
- (void)setFilterOnDiscoverPeripherals:(BOOL (^)(NSString *peripheralName, NSDictionary *advertisementData, NSNumber *rssi))filter
{
	self.filterPeripheralBlock = filter;
}

//扫描外设的block
- (void)bleCentralManagerDidDiscoverPeripheral:(void (^)(CBPeripheral *peripheral,NSDictionary* advertisementDict,NSNumber *rssi))callback
{
    self.discoverBlock  = callback;
}

//连接成功的block
- (void)bleCentralManagerDidConnectPeripheral:(void (^)(BOOL))callback
{
    self.connectBlock = callback;
}

//断开蓝牙的block
- (void)bleCentralManagerDisConnectedPeripheral:(void (^)(CBPeripheral *))callback
{
    self.connectedBlock = callback;
    
}

//读取rssi信号
- (void)blePeripheralDidReadRSSI:(void (^)(CBPeripheral *peripheral,NSNumber * rssi))callback
{
    self.readRSSIBlock = callback;
}

//读取可以写入数据的特质值
- (void)bleWriteValueforCharacteristic:(void (^)(CBPeripheral *peripheral,CBCharacteristic *curCharacteristic))callback
{
    self.txCharacteristic = callback;
}
/// 获取到WriteWithoutResponse特征值
- (void)bleWriteOutValueforCharacteristic:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic))callback{
    self.txOutCharacteristic = callback;
}

//读取外设数据
- (void)blePeripheralDidUpdateValue:(void (^)(CBPeripheral *peripheral,CBCharacteristic *curCharacteristic))callback
{
    self.valueBlock = callback;
}

//写入数据是否成功
//- (void)blePeripheralDidWriteValueSuccess:(void (^)(CBPeripheral *peripheral,CBCharacteristic *curCharacteristic,NSError *error))callback
//{
//    self.writeSuccess = callback;
//}

// MARK: -- 获取外设的服务 --
- (void)getPeripheralServices:(void (^_Nullable)(NSArray <CBService *>*_Nonnull services,NSError *_Nullable error))callback{
    self.getServicesBlock = callback;
}

// MARK: -- 获取外设的特征值 --
- (void)getPeripheralServicesForCharacteristics:(void (^)(NSArray<CBCharacteristic *> * _Nonnull notifys,NSArray<CBCharacteristic *> * _Nonnull writes,NSArray<CBCharacteristic *> * _Nonnull outWrites,NSArray<CBCharacteristic *> * _Nonnull reads, NSError * _Nullable error))callback{
    self.getCharacteristicsBlock = callback;
}

// MARK: -- 获取蓝牙状态 --
/// 获取蓝牙状态
- (void)getCentralManagerState:(void (^_Nullable)(BLECentralManagerState state))callback{
    self.bluetoothStateBlock = callback;
}

/// 写数据(有回应)
- (void)writeDataToPeripheral:(NSData *)data callback:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic,NSError *_Nullable error))callback{
    if (!data) {
        if (callback) {
            self.writeSuccess = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic, NSError *error) {
                callback(peripheral,curCharacteristic,error);
            };
        }
        return;
    }
    if (!self.m_TXCharacteristic) {
        if (callback) {
            self.writeSuccess = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic, NSError *error) {
                callback(peripheral,curCharacteristic,error);
            };
        }
        return;
    }
    if ([CurPeripheral shareInstance].currentPeripheral == nil) {
        if (callback) {
            self.writeSuccess = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic, NSError *error) {
                callback(peripheral,curCharacteristic,error);
            };
        }
        return;
    }
    [[CurPeripheral shareInstance].currentPeripheral writeValue:data
                                         forCharacteristic:self.m_TXCharacteristic
                                                    type:CBCharacteristicWriteWithResponse];
    if (callback) {
        self.writeSuccess = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic, NSError *error) {
            callback(peripheral,curCharacteristic,error);
        };
    }
    
}

// MARK: -- 写数据(无回应) --
- (void)writeoutDataToPeripheral:(NSData *)data callback:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic,NSError *_Nullable error))callback{
    if (!data) {
        if (callback) {
            self.writeSuccess = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic, NSError *error) {
                callback(peripheral,curCharacteristic,error);
            };
        }
        return;
    }
    if (!self.m_TXOutCharacteristic) {
        if (callback) {
            self.writeSuccess = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic, NSError *error) {
                callback(peripheral,curCharacteristic,error);
            };
        }
        return;
    }
    if ([CurPeripheral shareInstance].currentPeripheral == nil) {
        if (callback) {
            self.writeSuccess = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic, NSError *error) {
                callback(peripheral,curCharacteristic,error);
            };
        }
        return;
    }
    [[CurPeripheral shareInstance].currentPeripheral writeValue:data
                                         forCharacteristic:self.m_TXOutCharacteristic
                                                    type:CBCharacteristicWriteWithoutResponse];
    if (callback) {
        self.writeSuccess = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic, NSError *error) {
            callback(peripheral,curCharacteristic,error);
        };
    }
}


// MARK: -- 订阅通知 --
-(void)bleNotifyValue:(BOOL)enabled forCharacteristic:(CBCharacteristic *)characteristic callback:(void (^_Nullable)(CBPeripheral *peripheral, CBCharacteristic *characteristics))callback
{
    if (enabled) {
        if (characteristic &&  characteristic.properties & CBCharacteristicPropertyNotify) {
            [CURPERIPHERAL_INSTANCE.currentPeripheral setNotifyValue:true forCharacteristic:characteristic];
        }
    }else{
        if (characteristic &&  characteristic.properties & CBCharacteristicPropertyNotify) {
            [CURPERIPHERAL_INSTANCE.currentPeripheral setNotifyValue:false forCharacteristic:characteristic];
        }
    }
    if (callback) {
        self.valueBlock = ^(CBPeripheral *peripheral, CBCharacteristic *curCharacteristic) {
            if (curCharacteristic.properties & CBCharacteristicPropertyNotify) {
                callback(peripheral,curCharacteristic);
            }
        };
    }
}


- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI;
{
    self.bleState = scanning;
    //根据广播包带出来的设备名，初步判断
    NSString *name = peripheral.name;
    NSString *peripheralID = nil;
    if (name) {
        peripheralID = name;
    } else {
        peripheralID = advertisementData[@"kCBAdvDataLocalName"];
    }
//    NSLog(@"==========name:%@-------:%@",advertisementData,name);
	if (self.filterPeripheralBlock) {
		if (self.filterPeripheralBlock(peripheralID, advertisementData, RSSI)) {
//			NSLog(@"-----:%@----:%@-----:%@",peripheral,RSSI,advertisementData);
			if (self.stateTimer) {
				   [self.stateTimer invalidate];
			}
			self.stateTimer = [NSTimer timerWithTimeInterval:5.0 target:self selector:@selector(removeNonentityPeripheral) userInfo:nil repeats:NO];
			[[NSRunLoop mainRunLoop]addTimer:self.stateTimer forMode:NSRunLoopCommonModes];
			[self.stateTimer fireDate];
			if ([RSSI doubleValue]>=-100&&[RSSI doubleValue]<0) {
                [self comparePeripheralisEqual:peripheral.copy advertisementData:advertisementData RSSI:RSSI];
			}
			if (self.discoverBlock != nil) {
			   self.discoverBlock(peripheral.copy, advertisementData, RSSI);
			}
		}
	}else{
		//未设置过滤条件的情况
		if (self.stateTimer) {
				[self.stateTimer invalidate];
		 }
		 self.stateTimer = [NSTimer timerWithTimeInterval:5.0 target:self selector:@selector(removeNonentityPeripheral) userInfo:nil repeats:NO];
		 [[NSRunLoop mainRunLoop]addTimer:self.stateTimer forMode:NSRunLoopCommonModes];
		 [self.stateTimer fireDate];
		 if ([RSSI doubleValue]>=-100&&[RSSI doubleValue]<0) {
			[self comparePeripheralisEqual:peripheral.copy advertisementData:advertisementData RSSI:RSSI];
		 }
		
		 if (self.discoverBlock != nil) {
			self.discoverBlock(peripheral.copy, advertisementData, RSSI);
		 }
	}
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral;
{
    //停止计算器,停止扫描外设
    [self.scanTimer invalidate];
    [self.m_manger stopScan];
    //设置为全局属性,否则读取不到服务
    self.m_peripheral = peripheral.copy;
    self.m_peripheral.delegate = self;
    [self.m_peripheral discoverServices:nil];
    [self.m_peripheral readRSSI];
    [CURPERIPHERAL_INSTANCE setCurrentPeripheral:peripheral.copy];
    NSLog(@"已经连接上了: %@",peripheral.name);
    if (self.connectBlock != nil) {
        self.connectBlock(YES);
    }
    if (self.bluetoothStateBlock != nil) {
        self.bluetoothStateBlock(connecte);
    }
    
}
//连接指定外设
-(void)bleConnectPeripheral:(CBPeripheral *)peripheral options:(NSDictionary<NSString *,id> *)options{
    [self.m_manger connectPeripheral:peripheral options:options];
}

/// 连接指定外设
/// @param peripheralName 外设名
-(void)bleConnectPeripheralWithName:(NSString *_Nonnull)peripheralName callback:(void (^_Nullable)(BOOL isConnect))callback
{
    if (self.bleState == connecte) {
        if (callback) {
            callback(true);
        }
        return;
    }
    if (peripheralName && peripheralName.length > 1) {
        [self.m_array_peripheral enumerateObjectsUsingBlock:^(WDBLEPeripheral  *_Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([obj.m_peripheralLocaName isEqualToString:peripheralName]) {
                //去连接
                [self bleConnectPeripheral:obj.m_peripheral.copy options:nil];
                *stop = true;
                return;
            }
        }];
        if (callback) {
            self.connectBlock = ^(BOOL isConnect) {
                callback(isConnect);
            };
        }
    }
}
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error;
{
    static NSUInteger connectCount = 0;
    //苹果的官方解释{@link connectPeripheral:options:}链接外设失败了
    if (error && connectCount<3) {
        [self.m_manger connectPeripheral:peripheral options:nil];
        connectCount ++;
    }
    
    if (connectCount>=3) {
		NSLog(@"重连超过:%lu次",(unsigned long)connectCount);
        self.bleState = disconnect;
        return;
    }
    NSLog(@"链接外设失败:%@",error.localizedDescription);
}
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"连接蓝牙时错误:%@----:%@",error,characteristic);
    }
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error;
{
    //这个函数被调用是有前提条件的，首先你的要先调用过了 connectPeripheral:options:这个方法，其次是如果这个函数被回调的原因不是因为你主动调用了 cancelPeripheralConnection 这个方法，那么说明，整个蓝牙连接已经结束了，不会再有回连的可能
    //    NSLog(@"didDisconnectPeripheral==%@",error);
    
    //如果你想要尝试回连外设，可以在这里调用一下链接函数
    /*
     [central connectPeripheral:peripheral options:@{CBCentralManagerScanOptionSolicitedServiceUUIDsKey : @YES,CBConnectPeripheralOptionNotifyOnDisconnectionKey:@YES}];
     */
    // 开启定时器
    [self.scanTimer setFireDate:[NSDate distantPast]];
    // 计时器,扫描外设
    self.scanTimer =  [NSTimer scheduledTimerWithTimeInterval:SCAN_TIMER target:self selector:@selector(scanfunction) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop]addTimer:self.scanTimer forMode:NSRunLoopCommonModes];
    
    NSLog(@"断开蓝牙的错误码:%ld----:%@",(long)error.code,error.localizedDescription);
    if (error.code !=0) {
//        [central connectPeripheral:peripheral options:nil];
//        [self centralManager:central didRetriePeripherals:[[NSArray alloc]initWithObjects:peripheral, nil]];
    }
    if (self.connectedBlock != nil) {
        self.connectedBlock(peripheral);
    }
    [self.m_array_peripheral enumerateObjectsUsingBlock:^(WDBLEPeripheral *_Nonnull blePeri, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([blePeri.m_peripheralLocaName isEqualToString:peripheral.name]) {
            [self.m_array_peripheral removeObject:blePeri];
            if (self.discoverBlock != nil) {
                self.discoverBlock(nil, nil, nil);
            }
            //            NSLog(@"断开蓝牙后移除了指定的设备:%@",blePeri.m_peripheralLocaName);
            *stop = YES;
            return;
        }
    }];
    self.bleState = disconnect;
    if (self.bluetoothStateBlock != nil) {
        self.bluetoothStateBlock(disconnect);
    }
}


//断开重连
- (void)centralManager:(CBCentralManager *)central didRetriePeripherals:(NSArray *)peripherals
{
    for (CBPeripheral *peripheral in peripherals) {
        NSDictionary *connectOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:CBConnectPeripheralOptionNotifyOnDisconnectionKey];
        [central connectPeripheral:peripheral options:connectOptions];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error NS_AVAILABLE(NA, 8_0);
{
    if(self.readRSSIBlock != nil){
        self.readRSSIBlock(peripheral, RSSI);
    }
	[peripheral readRSSI];//方法回调的RSSI
    //    NSLog(@" peripheral Current RSSI:%@",RSSI);
    
}
// MARK: -- 发现外设的服务 --
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error;
{
    if (error) {
        NSLog(@"-------服务读取失败:%@------error:%@",peripheral.name,[error localizedDescription]);
        return;
    }
//    NSLog(@"蓝牙的服务:%@",peripheral.services);
    for (CBService *s in peripheral.services) {
        [peripheral discoverCharacteristics:nil forService:s];
    }
    self.services = peripheral.services;
//    if (self.getServicesBlock) {
//        self.getServicesBlock(peripheral.services, error);
//    }
}

// MARK: -- 发现特征值 --
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error;
{
    if (self.getServicesBlock) {
        self.getServicesBlock(peripheral.services, error);
    }
    NSMutableArray *notifyAry = [[NSMutableArray array]init];
    NSMutableArray *writeAry = [[NSMutableArray array]init];
    NSMutableArray *outWriteyAry = [[NSMutableArray array]init];
    NSMutableArray *readAry = [[NSMutableArray array]init];
    if (error) {
        self.m_NotifyCharacteristicAry = [notifyAry copy];
        if (self.getCharacteristicsBlock) {
            self.getCharacteristicsBlock(notifyAry, writeAry, outWriteyAry, readAry,error);
        }
        return;
    }
    self.m_peripheralMTU = [peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithResponse];
//    NSLog(@"--------Response:%ld",[peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithResponse]);
//    NSLog(@"--------outResponse:%ld",[peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithoutResponse]);
    BOOL writeFlage = false;
    BOOL writeOutFlage = false;
	for (CBCharacteristic *characteristic in service.characteristics) {
//        NSLog(@"--------:%@",characteristic);
		if (characteristic.properties & CBCharacteristicPropertyRead) {
			self.m_RXCharacteristic = characteristic;
            [readAry addObject:characteristic];
            [peripheral readValueForCharacteristic:characteristic];
		}
        if (characteristic.properties & CBCharacteristicPropertyWrite){
			self.m_TXCharacteristic = characteristic;
            [writeAry addObject:characteristic];
			//监听到服务再标识连接成功,防止有时连接后收不到服务,外界写入数据时崩溃现象
			self.bleState = connecte;
            if (!writeFlage) {
                writeFlage = true;
                if (self.txCharacteristic != nil) {
                   self.txCharacteristic(peripheral, characteristic);
                }
            }
		}
        if (characteristic.properties & CBCharacteristicPropertyNotify){
//			[peripheral setNotifyValue:true forCharacteristic:characteristic];
//            NSLog(@"--------通知的特征值:%@",characteristic);
            self.m_NotifyCharacteristic = characteristic;
            [notifyAry addObject:characteristic];
		}
        if (characteristic.properties & CBCharacteristicPropertyWriteWithoutResponse){
            self.m_TXOutCharacteristic = characteristic;
            [outWriteyAry addObject:characteristic];
            if (!writeOutFlage) {
                writeOutFlage = true;
                if (self.txOutCharacteristic != nil) {
                   self.txOutCharacteristic(peripheral, characteristic);
                }
            }
        }
		[peripheral discoverDescriptorsForCharacteristic:characteristic];
	}
    self.m_NotifyCharacteristicAry = [notifyAry copy];
    if (self.getCharacteristicsBlock) {
        self.getCharacteristicsBlock(notifyAry, writeAry, outWriteyAry, readAry, nil);
    }
  
}


- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error;
{
    if (error) {
        return;
    }
    //    Byte *resultByte = (Byte *)[characteristic.value bytes];
    //    for (int i = 0 ; i < [characteristic.value length]; i ++) {
    //        printf("resultByte = %x\n",resultByte[i]);
    //
    //    }
    //    NSString * resultSreing = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    //    NSLog(@"写的特质值:%@",resultSreing);
    if (self.valueBlock) {
        self.valueBlock(peripheral, characteristic);
    }
}


- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error;
{
    //发数据到外设的某一个特征值上面，并且响应的类型是 CBCharacteristicWriteWithResponse ，如果确定发送到外设了，就会给你一个回应，当然，这个也是要看外设那边的特征值UUID的属性是怎么设置的,条件是:特征值UUID的属性：CBCharacteristicWriteWithResponse
    
    if (!error) {
        NSLog(@"蓝牙命令发送成功");
    }else{
         NSLog(@"发送失败！characteristic.uuid为：%@",[characteristic.UUID UUIDString]);
    }
    if (self.writeSuccess) {
        self.writeSuccess(peripheral, characteristic, error);
    }
    
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    //这个方法被调用是因为你主动调用方法： setNotifyValue:forCharacteristic 给你的反馈
//    if ([[characteristic.UUID UUIDString]isEqual:RX_Characteristic_UUID]) {
//        [peripheral readValueForCharacteristic:characteristic];
//        NSLog(@"你更新了对特征值:%@ 的通知",[characteristic.UUID UUIDString]);
//    }
    
}

- (void)comparePeripheralisEqual:(CBPeripheral *)disCoverPeripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    [self.scanLock lock];
    CFTimeInterval curTime = CFAbsoluteTimeGetCurrent();
    NSString *key = disCoverPeripheral.identifier.UUIDString;
    [self.tmpDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull tmpKey, WDBLEPeripheral *_Nonnull objPer, BOOL * _Nonnull stop) {
        //比较时间,搜索出现时间较久远（10s）的移除搜索结果列表
        double time = curTime - objPer.m_peripheralTime;
        if (time >10.0) {
            [self.tmpDictionary removeObjectForKey:tmpKey];
        }
    }];
    WDBLEPeripheral *l_per = [[WDBLEPeripheral alloc]init];
    l_per.m_peripheral = disCoverPeripheral;
    l_per.m_peripheralIdentifier = key;
    l_per.m_peripheralUUID = key;
    l_per.m_peripheralLocaName = disCoverPeripheral.name;
    l_per.m_peripheralName = disCoverPeripheral.name;
    l_per.m_peripheralRSSI = RSSI;
    l_per.m_peripheralTime = CFAbsoluteTimeGetCurrent();
    l_per.advertisementData = advertisementData;
    [self.tmpDictionary setObject:l_per forKey:key];
    [self.m_array_peripheral removeAllObjects];
    [self.m_array_peripheral addObjectsFromArray:self.tmpDictionary.allValues];
    [self.scanLock unlock];
}

//取消BLE连接
- (void)cancelBLEConnection
{
    if (CURPERIPHERAL_INSTANCE.currentPeripheral!=nil) {
        if (CURPERIPHERAL_INSTANCE.currentPeripheral.state == CBPeripheralStateConnected) {
            [self.m_manger cancelPeripheralConnection:CURPERIPHERAL_INSTANCE.currentPeripheral]; //取消连接
        }
    }
}

- (void)removeNonentityPeripheral
{
    [self.m_array_peripheral removeAllObjects];
    //    NSLog(@"移除后的个数:%@",_m_array_peripheral);
    if (self.discoverBlock != nil) {
        self.discoverBlock(nil, nil, nil);
    }
}





@end
