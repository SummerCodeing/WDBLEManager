//
//  BluetoothTools
//
//  Created by summer on 2023/6/14.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "WDBLEPeripheral.h"

#define BLEMANAGER_INSTANCE [WDBLEManager shareInstance]

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BLECentralManagerState) {
	unknown = 0, ///<未知
	poweredOff, ///< 蓝牙关闭
	poweredOn,  ///<蓝牙开启
	scanning,   ///< 扫描外设
	connecte,   ///<连接状态
	disconnect, ///<断开连接
};

@interface WDBLEManager : NSObject

@property(nonatomic, strong) CBCentralManager *m_manger;
@property(nonatomic, strong) CBPeripheral    *m_peripheral;
@property(nonatomic, copy,nullable)   NSMutableArray  *m_array_peripheral;


@property(nonatomic, assign,readonly) BLECentralManagerState   bleState;              ///<状态
@property(nonatomic, strong,readonly,nullable) NSString       *m_peripheralName;      ///<连接上的设备名称
@property(nonatomic, strong,readonly,nonnull) CBCharacteristic *m_TXOutCharacteristic;  ///<写数据的特质值无响应
@property(nonatomic, strong,readonly,nonnull) CBCharacteristic *m_TXCharacteristic;     ///<写数据的特质值
@property(nonatomic, strong,readonly,nonnull) CBCharacteristic *m_RXCharacteristic;     ///<读数据的特质值
@property(nonatomic, strong,readonly,nonnull) CBCharacteristic *m_NotifyCharacteristic;  ///<通知的特征值
@property(nonatomic, assign,readonly) NSUInteger m_peripheralMTU;                     ///<连接的设备MTU
@property(nonatomic, copy,readonly) NSArray *m_NotifyCharacteristicAry;                ///<通知的特征值集合
@property(nonatomic, assign)BOOL isAutoReconnect;                                   ///<是否自动重连,默认false
@property(nonatomic,strong,readonly,nonnull)NSArray *services;

#pragma mark -- 设置相关 --
/**
 几秒搜索一次蓝牙外设(默认1.0秒/次)
 */
@property(nonatomic, strong,readonly)WDBLEManager *(^setTimeInterval)(double time);///<间隔时间(默认1.0秒/次)

/**
 设置查找Peripherals的规则搜索时指定的服务,默认搜索所有,后台搜索时必须指定Services
*/
@property(nonatomic, strong,readonly)WDBLEManager *(^setServices)(NSArray<CBUUID*> *services);///<搜索服务(默认搜索所有蓝牙设备)

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

+ (instancetype)shareInstance;

/**
 设置查找Peripherals的规则
*/
- (void)setFilterOnDiscoverPeripherals:(BOOL (^)(NSString *peripheralName, NSDictionary *advertisementData, NSNumber *rssi))filter;
/**
 扫描蓝牙外设

 @param callback 外设的参数
 */
- (void)bleCentralManagerDidDiscoverPeripheral:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,NSDictionary* _Nonnull advertisementDict,NSNumber *_Nonnull rssi))callback;


/// 连接蓝牙外设
/// @param peripheral 连接的外设
/// @param options 参数
-(void)bleConnectPeripheral:(CBPeripheral *_Nonnull)peripheral options:(NSDictionary<NSString *, id> *_Nullable)options;


/// 连接指定外设
/// @param peripheralName 外设名
-(void)bleConnectPeripheralWithName:(NSString *_Nonnull)peripheralName callback:(void (^_Nullable)(BOOL isConnect))callback;


/// 订阅通知
/// @param enabled  订阅/取消 True/false
/// @param characteristic characteristic-notify
/// @param callback true是有数据回调,false时,为nil
-(void)bleNotifyValue:(BOOL)enabled forCharacteristic:(CBCharacteristic *)characteristic callback:(void (^_Nullable)(CBPeripheral *peripheral, CBCharacteristic *characteristics))callback;
/**
 连接成功

 @param callback 是否连接成功
 */
- (void)bleCentralManagerDidConnectPeripheral:(void (^_Nullable)(BOOL isConnect))callback;

/**
 *  取消BLE连接
 */
- (void)cancelBLEConnection;

/**
 断开外设

 @param callback 断开的外设
 */
- (void)bleCentralManagerDisConnectedPeripheral:(void (^_Nullable)(CBPeripheral * _Nonnull peripheral))callback;


/**
 读取外设RSSI

 @param callback rssi值
 */
- (void)blePeripheralDidReadRSSI:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,NSNumber *_Nonnull rssi))callback;


/**
 获取到WriteWithResponse
   建议在次函数中写数据
 @param callback 可以写入数据的特质值
 */
- (void)bleWriteValueforCharacteristic:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic))callback;


/// 获取到WriteWithoutResponse特征值
/// @param callback 写数据的特征值
- (void)bleWriteOutValueforCharacteristic:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic))callback;
/**
 收到外设的数据

 @param callback 外设;外设的数据;当前特质值
 */
- (void)blePeripheralDidUpdateValue:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic))callback;


/// 写数据(有回应)
/// @param data 写入的数据
/// @param callback 外设;特质;成功/错误
- (void)writeDataToPeripheral:(NSData *)data callback:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic,NSError *_Nullable error))callback;


/// 写数据(无回应)
/// @param data 写入的数据
/// @param callback 外设;特质;成功/错误
- (void)writeoutDataToPeripheral:(NSData *)data callback:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic,NSError *_Nullable error))callback;

/// 获取外设的服务
/// @param callback 服务
- (void)getPeripheralServices:(void (^_Nullable)(NSArray <CBService *>*_Nonnull services,NSError *_Nullable error))callback;


/// 获取外设的特征值
/// @param callback 特征值数组
- (void)getPeripheralServicesForCharacteristics:(void (^)(NSArray<CBCharacteristic *> * _Nonnull notifys,NSArray<CBCharacteristic *> * _Nonnull writes,NSArray<CBCharacteristic *> * _Nonnull outWrites,NSArray<CBCharacteristic *> * _Nonnull reads, NSError * _Nullable error))callback;


/// 获取蓝牙状态
/// @param callback 蓝牙状态
- (void)getCentralManagerState:(void (^_Nullable)(BLECentralManagerState state))callback;

/**
 写入数据是否成功

 @param callback 外设;特质;成功/错误
 */
//- (void)blePeripheralDidWriteValueSuccess:(void (^_Nullable)(CBPeripheral *_Nonnull peripheral,CBCharacteristic *_Nonnull curCharacteristic,NSError *_Nonnull error))callback;

@end

NS_ASSUME_NONNULL_END
