import Flutter
import Foundation
import PusherSwift
import UIKit

public class SwiftPusherChannelsFlutterPlugin: NSObject, FlutterPlugin, PusherDelegate, Authorizer {
  private var pusher: Pusher!
  public var methodChannel: FlutterMethodChannel!

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftPusherChannelsFlutterPlugin()
    instance.methodChannel = FlutterMethodChannel(name: "pusher_channels_flutter", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: instance.methodChannel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
      initChannels(call: call, result: result)
    case "connect":
      connect(result: result)
    case "disconnect":
      disconnect(result: result)
    case "getSocketId":
      getSocketId(result: result)
    case "subscribe":
      subscribe(call: call, result: result)
    case "unsubscribe":
      unsubscribe(call: call, result: result)
    case "trigger":
      trigger(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func initChannels(call: FlutterMethodCall, result: @escaping FlutterResult) {
    if pusher != nil {
        pusher.disconnect()
    }
    let args = call.arguments as! [String: Any]
    var authMethod: AuthMethod = .noMethod
    if args["authEndpoint"] is String {
      authMethod = .endpoint(authEndpoint: args["authEndpoint"] as! String)
    } else if args["authorizer"] is Bool {
      authMethod = .authorizer(authorizer: self)
    }
    var host: PusherHost = .defaultHost
    if args["host"] is String {
      host = .host(args["host"] as! String)
    } else if args["cluster"] != nil {
      host = .cluster(args["cluster"] as! String)
    }
    var useTLS: Bool = true
    if args["useTLS"] is Bool {
      useTLS = args["useTLS"] as! Bool
    }
    var port: Int
    if useTLS {
      port = 443
      if args["wssPort"] is Int {
        port = args["wssPort"] as! Int
      }
    } else {
      port = 80
      if args["wsPort"] is Int {
        port = args["wsPort"] as! Int
      }
    }
    var activityTimeout: TimeInterval?
    if args["activityTimeout"] is TimeInterval {
      activityTimeout = args["activityTimeout"] as! Double / 1000.0
    }
    var path: String?
    if args["path"] is String {
      path = (args["path"] as! String)
    }
    let options = PusherClientOptions(
      authMethod: authMethod,
      host: host,
      port: port,
      path: path,
      useTLS: useTLS,
      activityTimeout: activityTimeout
    )
    pusher = Pusher(key: args["apiKey"] as! String, options: options)
    if args["maxReconnectionAttempts"] is Int {
      pusher.connection.reconnectAttemptsMax = (args["maxReconnectionAttempts"] as! Int)
    }
    if args["maxReconnectGapInSeconds"] is TimeInterval {
      pusher.connection.maxReconnectGapInSeconds = (args["maxReconnectGapInSeconds"] as! TimeInterval)
    }
    if args["pongTimeout"] is Int {
      pusher.connection.pongResponseTimeoutInterval = args["pongTimeout"] as! TimeInterval / 1000.0
    }
    pusher.connection.delegate = self
    pusher.bind(eventCallback: onEvent)
    result(nil)
  }

public func fetchAuthValue(socketID: String, channelName: String, completionHandler: @escaping (PusherAuth?) -> Void) {
    print("[PusherPlugin] Custom auth request for socket: \(socketID), channel: \(channelName)")

    // Replace with your actual endpoint
    guard let url = URL(string: "https://apishopping-daddy-main-eouxm5.laravel.cloud/api/broadcasting/auth") else {
        print("[PusherPlugin] Invalid auth URL")
        completionHandler(nil)
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    // Set form-encoded body like Laravel expects
    let bodyString = "socket_id=\(socketID)&channel_name=\(channelName)"
    request.httpBody = bodyString.data(using: .utf8)
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    // Add bearer token (from secure store or however your app authenticates)
    if let token = UserDefaults.standard.string(forKey: "token") {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // Perform the request
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        guard error == nil else {
            print("[PusherPlugin] Auth request failed:", error!.localizedDescription)
            completionHandler(nil)
            return
        }

        guard let data = data else {
            print("[PusherPlugin] No auth response data")
            completionHandler(nil)
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let auth = json["auth"] as? String {
                let channelData = json["channel_data"] as? String
                let sharedSecret = json["shared_secret"] as? String

                print("[PusherPlugin] Auth success: \(auth)")
                completionHandler(PusherAuth(auth: auth, channelData: channelData, sharedSecret: sharedSecret))
            } else {
                print("[PusherPlugin] Invalid auth JSON")
                completionHandler(nil)
            }
        } catch {
            print("[PusherPlugin] JSON decode error:", error.localizedDescription)
            completionHandler(nil)
        }
    }

    task.resume()
}




public func changedConnectionState(from old: ConnectionState, to new: ConnectionState) {
  DispatchQueue.main.async {
    self.methodChannel.invokeMethod("onConnectionStateChange", arguments: [
      "previousState": old.stringValue(),
      "currentState": new.stringValue(),
    ])
  }
}

  public func debugLog(message _: String) {
    // print("DEBUG:", message)
  }

  public func subscribedToChannel(name _: String) {
    // Handled by global handler
  }

 public func failedToSubscribeToChannel(name _: String, response _: URLResponse?, data _: String?, error: NSError?) {
   DispatchQueue.main.async {
     self.methodChannel.invokeMethod(
       "onSubscriptionError", arguments: [
         "message": (error != nil) ? error!.localizedDescription : "",
         "error": error.debugDescription,
       ]
     )
   }
 }


public func receivedError(error: PusherError) {
  DispatchQueue.main.async {
    self.methodChannel.invokeMethod(
      "onError", arguments: [
        "message": error.message,
        "code": error.code ?? -1,
        "error": error.debugDescription,
      ]
    )
  }
}

 public func failedToDecryptEvent(eventName: String, channelName _: String, data: String?) {
   DispatchQueue.main.async {
     self.methodChannel.invokeMethod(
       "onDecryptionFailure", arguments: [
         "eventName": eventName,
         "reason": data,
       ]
     )
   }
 }

  func connect(result: @escaping FlutterResult) {
    pusher.connect()
    result(nil)
  }

  func disconnect(result: @escaping FlutterResult) {
    pusher.disconnect()
    result(nil)
  }

  func getSocketId(result: @escaping FlutterResult) {
    result(pusher.connection.socketId)
  }

func onEvent(event: PusherEvent) {
  var userId: String?
  if event.eventName == "pusher:subscription_succeeded" {
    if let channel = pusher.connection.channels.findPresence(name: event.channelName!) {
      userId = channel.myId
    }
  }
  DispatchQueue.main.async {
    self.methodChannel.invokeMethod(
      "onEvent", arguments: [
        "channelName": event.channelName,
        "eventName": event.eventName,
        "userId": event.userId ?? userId,
        "data": event.data,
      ]
    )
  }
}

func subscribe(call: FlutterMethodCall, result: @escaping FlutterResult) {
  let args = call.arguments as! [String: String]
  let channelName: String = args["channelName"]!
  if channelName.hasPrefix("presence-") {
    let onMemberAdded: (PusherPresenceChannelMember) -> Void = { user in
      DispatchQueue.main.async {
        self.methodChannel.invokeMethod("onMemberAdded", arguments: [
          "channelName": channelName,
          "user": ["userId": user.userId, "userInfo": user.userInfo],
        ])
      }
    }
    let onMemberRemoved: (PusherPresenceChannelMember) -> Void = { user in
      DispatchQueue.main.async {
        self.methodChannel.invokeMethod("onMemberRemoved", arguments: [
          "channelName": channelName,
          "user": ["userId": user.userId, "userInfo": user.userInfo],
        ])
      }
    }
    pusher.subscribeToPresenceChannel(
      channelName: channelName,
      onMemberAdded: onMemberAdded,
      onMemberRemoved: onMemberRemoved
    )
  } else {
    let onSubscriptionCount: (Int) -> Void = { subscriptionCount in
      DispatchQueue.main.async {
        self.methodChannel.invokeMethod(
          "onEvent", arguments: [
            "channelName": channelName,
            "eventName": "pusher:subscription_count",
            "userId": nil,
            "data": [
              "subscription_count": subscriptionCount,
            ],
          ]
        )
      }
    }
    pusher.subscribe(channelName: channelName,
                     onSubscriptionCountChanged: onSubscriptionCount)
  }
  result(nil)
}

  func unsubscribe(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as! [String: String]
    let channelName: String = args["channelName"]!
    pusher.unsubscribe(channelName)
    result(nil)
  }

  func trigger(call: FlutterMethodCall, result _: @escaping FlutterResult) {
    let args = call.arguments as! [String: String]
    let channelName: String = args["channelName"]!
    let eventName: String = args["eventName"]!
    let data: String? = args["data"]
    if let channel = pusher.connection.channels.find(name: channelName) {
      channel.trigger(eventName: eventName, data: data as Any)
    }
  }
}
