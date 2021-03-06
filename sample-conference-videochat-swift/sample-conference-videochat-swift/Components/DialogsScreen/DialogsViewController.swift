//
//  DialogsViewController.swift
//  sample-conference-videochat-swift
//
//  Created by Injoit on 9/30/19.
//  Copyright © 2019 Quickblox. All rights reserved.
//

import UIKit
import Quickblox
import QuickbloxWebRTC
import SVProgressHUD
import UserNotifications

struct DialogsConstant {
    static let dialogsPageLimit:Int = 100
    static let segueGoToChat = "goToChat"
    static let selectOpponents = "SelectOpponents"
    static let infoSegue = "PresentInfoViewController"
    static let deleteChats = "Delete Chats"
    static let forward = "Forward to"
    static let deleteDialogs = "deleteDialogs"
    static let chats = "Chats"
    static let call = "PresentCallViewController"
    static let onCall = "onCall"
}

class DialogTableViewCellModel: NSObject {
    
    //MARK: - Properties
    var textLabelText: String = ""
    var unreadMessagesCounterLabelText : String?
    var unreadMessagesCounterHiden = true
    var dialogIcon : UIImage?
    
    //MARK: - Life Cycle
    init(dialog: QBChatDialog) {
        super.init()
        
        textLabelText = dialog.name ?? "UN"
        // Unread messages counter label
        if dialog.unreadMessagesCount > 0 {
            var trimmedUnreadMessageCount = ""
            
            if dialog.unreadMessagesCount > 99 {
                trimmedUnreadMessageCount = "99+"
            } else {
                trimmedUnreadMessageCount = String(format: "%d", dialog.unreadMessagesCount)
            }
            unreadMessagesCounterLabelText = trimmedUnreadMessageCount
            unreadMessagesCounterHiden = false
        } else {
            unreadMessagesCounterLabelText = nil
            unreadMessagesCounterHiden = true
        }
        
        if dialog.type == .private {
            if dialog.recipientID == -1 {
                return
            }
            // Getting recipient from users.
            if let recipient = ChatManager.instance.storage.user(withID: UInt(dialog.recipientID)),
                let fullName = recipient.fullName {
                self.textLabelText = fullName
            } else {
                ChatManager.instance.loadUser(UInt(dialog.recipientID)) { [weak self] (user) in
                    self?.textLabelText = user?.fullName ?? user?.login ?? ""
                }
            }
        } else {
        }
    }
}

class DialogsViewController: UITableViewController {
    //MARK: - Properties
    private let chatManager = ChatManager.instance
    private var dialogs: [QBChatDialog] = []
    private var cancel = false
    
    //MARK: - Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(UINib(nibName: DialogCellConstant.reuseIdentifier, bundle: nil), forCellReuseIdentifier: DialogCellConstant.reuseIdentifier)
        setupNavigationBar()
        setupNavigationTitle()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        reloadContent()
        
        chatManager.delegate = self
        if QBChat.instance.isConnected == false {
            ChatManager.instance.connect { (error) in
                if error != nil {
                    SVProgressHUD.showSuccess(withStatus: "QBChat is not Connected")
                }
            }
        }
        
        chatManager.updateStorage()
        
        let tapGestureDelete = UILongPressGestureRecognizer(target: self, action: #selector(tapEdit(_:)))
        tapGestureDelete.minimumPressDuration = 0.3
        tapGestureDelete.delaysTouchesBegan = true
        tableView.addGestureRecognizer(tapGestureDelete)
        
        //MARK: - Reachability
        let updateConnectionStatus: ((_ status: NetworkConnectionStatus) -> Void)? = { [weak self] status in
            let notConnection = status == .notConnection
            if notConnection == true {
                self?.showAlertView(LoginConstant.checkInternet, message: LoginConstant.checkInternetMessage)
            }
        }
        Reachability.instance.networkStatusBlock = { status in
            updateConnectionStatus?(status)
        }
        
        CallPermissions.check(with: .video) { granted in
            if granted {
                self.registerForRemoteNotifications()
                debugPrint("[DialogsViewController] granted!")
            } else {
                self.registerForRemoteNotifications()
                debugPrint("[DialogsViewController] granted canceled!")
            }
        }
    }
    
    //MARK: - Setup
    private func registerForRemoteNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.sound, .alert, .badge], completionHandler: { granted, error in
            if let error = error {
                debugPrint("[AuthorizationViewController] registerForRemoteNotifications error: \(error.localizedDescription)")
                return
            }
            center.getNotificationSettings(completionHandler: { settings in
                if settings.authorizationStatus != .authorized {
                    return
                }
                DispatchQueue.main.async(execute: {
                    UIApplication.shared.registerForRemoteNotifications()
                })
            })
        })
    }
    
    private func setupNavigationBar() {
        let currentUser = Profile()
        let fullName = String(currentUser.fullName.capitalized.first ?? Character("U"))
        
        let profileBarButton = UIButton(frame: CGRect(x:0, y:0, width:28.0, height:28.0))
        profileBarButton.titleLabel?.font = .systemFont(ofSize: 13.0, weight: .semibold)
        profileBarButton.setTitle(fullName, for: .normal)
        profileBarButton.setTitle(fullName, for: .highlighted)
        profileBarButton.backgroundColor = currentUser.ID.generateColor()
        profileBarButton.layer.cornerRadius = 14.0
        profileBarButton.addTarget(self, action: #selector(didTapMenu(_:)), for: .touchUpInside)
        
        let leftBarButtonItem = UIBarButtonItem(customView: profileBarButton)
        self.navigationItem.leftBarButtonItem = leftBarButtonItem
        
        let usersButtonItem = UIBarButtonItem(image: UIImage(named: "add"),
                                              style: .plain,
                                              target: self,
                                              action: #selector(didTapNewChat(_:)))
        navigationItem.rightBarButtonItem = usersButtonItem
        usersButtonItem.tintColor = .white
    }
    
    @objc func tapEdit(_ gestureReconizer: UILongPressGestureRecognizer) {
        if gestureReconizer.state != UIGestureRecognizer.State.ended {
            if let deleteVC = storyboard?.instantiateViewController(withIdentifier: "DialogsSelectionVC") as? DialogsSelectionVC {
                deleteVC.action = ChatActions.Delete
                let navVC = UINavigationController(rootViewController: deleteVC)
                navVC.navigationBar.barTintColor = #colorLiteral(red: 0.2216441333, green: 0.4713830948, blue: 0.9869660735, alpha: 1)
                navVC.navigationBar.barStyle = .black
                navVC.navigationBar.shadowImage = UIImage(named: "navbar-shadow")
                navVC.navigationBar.isTranslucent = false
                navVC.modalPresentationStyle = .fullScreen
                present(navVC, animated: false) {
                    self.tableView.removeGestureRecognizer(gestureReconizer)
                }
            }
        }
    }
    
    @objc func didTapInfo(_ sender: UIBarButtonItem) {
        performSegue(withIdentifier: DialogsConstant.infoSegue, sender: sender)
    }
    
    @objc func didTapNewChat(_ sender: UIBarButtonItem) {
        performSegue(withIdentifier: DialogsConstant.selectOpponents, sender: sender)
    }
    
    @objc func didTapMenu(_ sender: UIBarButtonItem) {
        let chatStoryboard = UIStoryboard(name: "Chat", bundle: nil)
        guard let popVC = chatStoryboard.instantiateViewController(withIdentifier: "ChatPopVC") as? ChatPopVC else {
            return
        }
        popVC.typePopVC = .hamburger
        popVC.actions = [.UserProfile, .VideoConfig, .AudioConfig, .AppInfo, .Logout]
        popVC.modalPresentationStyle = .popover
        let chatPopOverVc = popVC.popoverPresentationController
        chatPopOverVc?.delegate = self
        chatPopOverVc?.barButtonItem = navigationItem.leftBarButtonItem 
        chatPopOverVc?.permittedArrowDirections = UIPopoverArrowDirection(rawValue: 0)
        popVC.selectedAction = { [weak self] selectedAction in
            guard let action = selectedAction else {
                return
            }
            self?.handleAction(action)
        }
        present(popVC, animated: false)
    }
    
    private func handleAction(_ action: ChatActions) {
        switch action {
        case .UserProfile: print("User Profile")
        case .Logout: didTapLogout()
        case .VideoConfig: performSegue(withIdentifier: "SA_STR_SEGUE_GO_TO_VIDEO_CONFIGURATION".localized, sender: nil)
        case .AudioConfig: performSegue(withIdentifier: "SA_STR_SEGUE_GO_TO_AUDIO_CONFIGURATION".localized, sender: nil)
        case .AppInfo: performSegue(withIdentifier: DialogsConstant.infoSegue, sender: nil)
        default: break
        }
    }
    
    private func didTapLogout() {
        if QBChat.instance.isConnected == true {
            SVProgressHUD.show(withStatus: "SA_STR_LOGOUTING".localized)
            SVProgressHUD.setDefaultMaskType(.clear)
            
            guard let identifierForVendor = UIDevice.current.identifierForVendor else {
                return
            }
            let uuidString = identifierForVendor.uuidString
            #if targetEnvironment(simulator)
            disconnectUser()
            #else
            QBRequest.subscriptions(successBlock: { (response, subscriptions) in
                if let subscriptions = subscriptions {
                    for subscription in subscriptions {
                        if let subscriptionsUIUD = subscriptions.first?.deviceUDID,
                            subscriptionsUIUD == uuidString,
                            subscription.notificationChannel == .APNS {
                            self.unregisterSubscription(forUniqueDeviceIdentifier: uuidString)
                            return
                        }
                    }
                }
                self.disconnectUser()
                
            }) { response in
                if response.status.rawValue == 404 {
                    self.disconnectUser()
                }
            }
            #endif
        } else {
            ChatManager.instance.connect { [weak self] (error) in
                if let error = error {
                    self?.showAlertView(error.localizedDescription, message: LoginConstant.checkInternetMessage)
                }
            }
        }
    }
    
    private func unregisterSubscription(forUniqueDeviceIdentifier uuidString: String) {
        QBRequest.unregisterSubscription(forUniqueDeviceIdentifier: uuidString, successBlock: { response in
            self.disconnectUser()
        }, errorBlock: { error in
            if let error = error.error {
                SVProgressHUD.showError(withStatus: error.localizedDescription)
                return
            }
            SVProgressHUD.dismiss()
        })
    }
    
    //MARK: - Internal Methods
    private func hasConnectivity() -> Bool {
        let status = Reachability.instance.networkConnectionStatus()
        guard status != NetworkConnectionStatus.notConnection else {
            showAlertView(LoginConstant.checkInternet, message: LoginConstant.checkInternetMessage)
            return false
        }
        return true
    }
    
    private func disconnectUser() {
        QBChat.instance.disconnect(completionBlock: { error in
            if let error = error {
                SVProgressHUD.showError(withStatus: error.localizedDescription)
                return
            }
            self.logOut()
        })
    }
    
    private func logOut() {
        QBRequest.logOut(successBlock: { [weak self] response in
            //ClearProfile
            Profile.clearProfile()
            self?.chatManager.storage.clear()
            CacheManager.shared.clearCache()
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + .seconds(1)) {
                AppDelegate.shared.rootViewController.showLoginScreen()
            }
            SVProgressHUD.showSuccess(withStatus: "SA_STR_COMPLETED".localized)
        }) { response in
            debugPrint("[DialogsViewController] logOut error: \(response)")
        }
    }
    
    // MARK: - UITableViewDataSource
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dialogs.count
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60.0
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: DialogCellConstant.reuseIdentifier,
                                                       for: indexPath) as? DialogCell else {
                                                        return UITableViewCell()
        }
        
        cell.isExclusiveTouch = true
        cell.contentView.isExclusiveTouch = true
        cell.tag = indexPath.row
        
        let chatDialog = dialogs[indexPath.row]
        let cellModel = DialogTableViewCellModel(dialog: chatDialog)
        
        tableView.allowsMultipleSelection = false
        cell.checkBoxImageView.isHidden = true
        cell.checkBoxView.isHidden = true
        cell.unreadMessageCounterLabel.isHidden = false
        cell.unreadMessageCounterHolder.isHidden = false
        cell.lastMessageDateLabel.isHidden = false
        cell.contentView.backgroundColor = .clear
        
        if let dateSend = chatDialog.lastMessageDate {
            cell.lastMessageDateLabel.text = setupDate(dateSend)
        } else if let dateUpdate = chatDialog.updatedAt {
            cell.lastMessageDateLabel.text = setupDate(dateUpdate)
        }
        
        cell.unreadMessageCounterLabel.text = cellModel.unreadMessagesCounterLabelText
        cell.unreadMessageCounterHolder.isHidden = cellModel.unreadMessagesCounterHiden
        
        cell.dialogLastMessage.text = chatDialog.lastMessageText
        if chatDialog.lastMessageText == nil && chatDialog.lastMessageID != nil {
            cell.dialogLastMessage.text = "[Attachment]"
        }
        if let dateSend = chatDialog.lastMessageDate {
            cell.lastMessageDateLabel.text = setupDate(dateSend)
        } else if let dateUpdate = chatDialog.updatedAt {
            cell.lastMessageDateLabel.text = setupDate(dateUpdate)
        }
        cell.joinButton.isHidden = true
        cell.streamImageView.isHidden = true
        cell.lastMessageDateLabel.isHidden = false
        cell.dialogName.text = cellModel.textLabelText
        cell.dialogAvatarLabel.backgroundColor = UInt(chatDialog.createdAt!.timeIntervalSince1970).generateColor()
        cell.dialogAvatarLabel.text = String(cellModel.textLabelText.stringByTrimingWhitespace().capitalized.first ?? Character("C"))
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        tableView.deselectRow(at: indexPath, animated: true)
        let dialog = dialogs[indexPath.row]
        if let dialogID = dialog.id {
            openChatWithDialogID(dialogID)
        }
    }
    
    func openChatWithDialogID(_ dialogID: String) {
        let chatParentVC = ChatParentVC(dialogID: dialogID)
        chatParentVC.modalPresentationStyle = .fullScreen
        present(chatParentVC, animated: true, completion: nil)
    }
    
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let dialog = dialogs[indexPath.row]
        if dialog.type == .publicGroup {
            return false
        }
        return true
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle,
                            forRowAt indexPath: IndexPath) {
        if Reachability.instance.networkConnectionStatus() == .notConnection {
            showAlertView(LoginConstant.checkInternet, message: LoginConstant.checkInternetMessage)
            return
        }
        
        if QBChat.instance.isConnected == true {
            let dialog = dialogs[indexPath.row]
            if editingStyle != .delete || dialog.type == .publicGroup {
                return
            }
            
            let alertController = UIAlertController(title: "SA_STR_WARNING".localized,
                                                    message: "SA_STR_DO_YOU_REALLY_WANT_TO_DELETE_SELECTED_DIALOG".localized,
                                                    preferredStyle: .alert)
            
            let cancelAction = UIAlertAction(title: "SA_STR_CANCEL".localized, style: .cancel, handler: nil)
            
            let leaveAction = UIAlertAction(title: "SA_STR_DELETE".localized, style: .default) { (action:UIAlertAction) in
                SVProgressHUD.show(withStatus: "SA_STR_DELETING".localized)
                
                guard let dialogID = dialog.id else {
                    SVProgressHUD.dismiss()
                    return
                }
                
                if dialog.type == .private {
                    self.chatManager.leaveDialog(withID: dialogID)
                } else {
                    
                    let currentUser = Profile()
                    guard currentUser.isFull == true else {
                        return
                    }
                    // group
                    dialog.pullOccupantsIDs = [(NSNumber(value: currentUser.ID)).stringValue]
                    
                    let message = "\(currentUser.fullName) " + "SA_STR_USER_HAS_LEFT".localized
                    // Notifies occupants that user left the dialog.
                    self.chatManager.sendLeaveMessage(message, to: dialog, completion: { (error) in
                        if let error = error {
                            debugPrint("[DialogsViewController] sendLeaveMessage error: \(error.localizedDescription)")
                            SVProgressHUD.dismiss()
                            return
                        }
                        self.chatManager.leaveDialog(withID: dialogID)
                    })
                }
            }
            alertController.addAction(cancelAction)
            alertController.addAction(leaveAction)
            present(alertController, animated: true, completion: nil)
        } else {
            ChatManager.instance.connect { (error) in
                if error != nil {
                    SVProgressHUD.showSuccess(withStatus: "QBChat is not Connected")
                }
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
        return "SA_STR_DELETE".localized
    }
    
    // MARK: - Helpers
    private func reloadContent() {
        dialogs = chatManager.storage.dialogsSortByUpdatedAt()
        tableView.reloadData()
    }
    
    fileprivate func setupDate(_ dateSent: Date) -> String {
        let formatter = DateFormatter()
        var dateString = ""
        
        if Calendar.current.isDateInToday(dateSent) == true {
            dateString = messageTimeDateFormatter.string(from: dateSent)
        } else if Calendar.current.isDateInYesterday(dateSent) == true {
            dateString = "Yesterday"
        } else if dateSent.hasSame([.year], as: Date()) == true {
            formatter.dateFormat = "d MMM"
            dateString = formatter.string(from: dateSent)
        } else {
            formatter.dateFormat = "d.MM.yy"
            var anotherYearDate = formatter.string(from: dateSent)
            if (anotherYearDate.hasPrefix("0")) {
                anotherYearDate.remove(at: anotherYearDate.startIndex)
            }
            dateString = anotherYearDate
        }
        
        return dateString
    }
    
    private func setupNavigationTitle() {
        self.title = DialogsConstant.chats
    }
}

// MARK: - QBChatDelegate
extension DialogsViewController: QBChatDelegate {
    func chatRoomDidReceive(_ message: QBChatMessage, fromDialogID dialogID: String) {
        chatManager.updateDialog(with: dialogID, with: message)
    }
    
    func chatDidReceive(_ message: QBChatMessage) {
        guard let dialogID = message.dialogID else {
            return
        }
        chatManager.updateDialog(with: dialogID, with: message)
    }
    
    func chatDidReceiveSystemMessage(_ message: QBChatMessage) {
        if message.senderID != Profile().ID,
            message.customParameters[ChatDataSourceConstant.isCameraEnabled] as? String != nil,
            let roomID = message.customParameters[ChatDataSourceConstant.roomID] as? String,
            let userID = message.customParameters[ChatDataSourceConstant.userID] as? String,
            let isCameraEnabled = message.customParameters[ChatDataSourceConstant.isCameraEnabled] as? String {
            NotificationCenter.default.post(name: ChatViewControllerConstant.cameraEnabledMessageNotification,
                                            object: nil,
                                            userInfo: ["roomID" : roomID, "userID" : userID, "isCameraEnabled" : isCameraEnabled])
            return
        }
        
        guard let dialogID = message.dialogID else {
            return
        }
        
        if let _ = chatManager.storage.dialog(withID: dialogID) {
            return
        }
        chatManager.updateDialog(with: dialogID, with: message)
    }
    
    func chatServiceChatDidFail(withStreamError error: Error) {
        SVProgressHUD.showError(withStatus: error.localizedDescription)
    }
    
    func chatDidAccidentallyDisconnect() {
    }
    
    func chatDidNotConnectWithError(_ error: Error) {
        SVProgressHUD.showError(withStatus: error.localizedDescription)
    }
    
    func chatDidDisconnectWithError(_ error: Error) {
    }
    
    func chatDidConnect() {
        if QBChat.instance.isConnected == true {
            chatManager.updateStorage()
            SVProgressHUD.showSuccess(withStatus: "SA_STR_CONNECTED".localized)
        }
    }
    
    func chatDidReconnect() {
        SVProgressHUD.show(withStatus: "SA_STR_CONNECTED".localized)
        if QBChat.instance.isConnected == true {
            chatManager.updateStorage()
            SVProgressHUD.showSuccess(withStatus: "SA_STR_CONNECTED".localized)
        }
    }
}

// MARK: - ChatManagerDelegate
extension DialogsViewController: ChatManagerDelegate {
    func chatManager(_ chatManager: ChatManager, didUpdateChatDialog chatDialog: QBChatDialog, isOnCall: Bool?) {
        reloadContent()
        SVProgressHUD.dismiss()
    }
    
    func chatManager(_ chatManager: ChatManager, didFailUpdateStorage message: String) {
        SVProgressHUD.showError(withStatus: message)
    }
    
    func chatManager(_ chatManager: ChatManager, didUpdateStorage message: String) {
        reloadContent()
        SVProgressHUD.dismiss()
        QBChat.instance.addDelegate(self)
    }
    
    func chatManagerWillUpdateStorage(_ chatManager: ChatManager) {
        if navigationController?.topViewController == self {
            
        }
    }
}

//MARK: - UIPopoverPresentationControllerDelegate
extension DialogsViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
}
