//
//  CheckAnswerViewModel.swift
//  ABloom
//
//  Created by Lee Jinhee on 11/20/23.
//

import Foundation

@MainActor
final class CheckAnswerViewModel: ObservableObject {
  var dbQuestion: DBStaticQuestion = DBStaticQuestion(questionID: 1, category: "", content: "")
  @Published var isDataReady = false
  
  @Published var currentUser: DBUser?
  @Published var fianceUser: DBUser?
  
  @Published var currentUserAnswer: DBAnswer?
  @Published var fianceAnswer: DBAnswer?
  @Published var currentUserAnswerId: String?
  @Published var fianceAnswerId: String?
  
  @Published var currentUserName: String = "사용자"
  @Published var fianceName: String = "상대방"
  
  @Published var recentDate: Date = .distantPast
    
  @Published var showSelectReactionView: Bool = false
  @Published var selectedReaction: ReactionStatus = .noReact(.wait)
  
  @Published var isAnswersDone: Bool = false
  
  private var currentUserAnswerStatus: CurrentUserAnswerStatus = .noAnswered
  private var fianceAnswerStatus: FianceAnswerStatus = .noAnswered
  
  @Published var currentUserReactionStatus: ReactionStatus = .noReact(.plus)
  @Published var fianceReactionStatus: ReactionStatus = .noReact(.lock)
  
  var currentUserAnswerContent: String {
    switch currentUserAnswerStatus {
    case .noAnswered:
      "\(fianceName)님의 답변을 확인해보려면 나의 답변도 작성해주세요."
    case .answered:
      currentUserAnswer?.answerContent ?? ""
    }
  }
  
  var fianceAnswerContent: String {
    switch fianceAnswerStatus {
    case .unconnected:
      "상대방과 연결되어 있지 않아요. 연결되면 우리만의 문답을 함께 작성해갈 수 있어요."
    case .noAnswered:
      "상대방의 답변을 기다리고 있어요. 답변이 작성되면 푸쉬 알림으로 알려드릴게요."
    case .answered:
      if currentUserAnswerStatus == .answered {
        fianceAnswer?.answerContent ?? ""
      } else {
        "잠겨있어요!"
      }
    }
  }
  
  var coupleReaction: String {
    switch (currentUserReactionStatus, fianceReactionStatus) {
    case (.react(let currentUserReaction), .react(let fianceReaction)):
      if [currentUserReaction, fianceReaction].contains(.moreCommunication) {
        return "5_Communicate"
      } else if [currentUserReaction, fianceReaction].contains(.moreResearch) {
        return "7_LetsKnow"
      } else {
        return "6_Good"
      }
    case (_, _):
      return "A_Lock"
    }
  }
  
  func getAnswers(dbQuestion: DBStaticQuestion) {
    self.isDataReady = false
    self.dbQuestion = dbQuestion
    
    Task {
      getCurrentUser()
      getFianceUser()
      
      try? await getMyAnswer()
      try? await getFianceAnswer()
      
      self.isAnswersDone = (currentUserAnswer != nil && fianceAnswer != nil)
      
      getRecentDate()
      
      checkReactions()
      
      self.isDataReady = true
    }
  }
  
  // MARK: - 최근 날짜 불러오기
  private func getRecentDate() {
    getcurrentUserAnswerDate()
    getFianceAnswerDate()
  }
  
  private func getcurrentUserAnswerDate() {
    guard let currentUserDate = self.currentUserAnswer?.date else { return }
    self.recentDate = currentUserDate
  }
  
  private func getFianceAnswerDate() {
    guard let fianceDate = self.fianceAnswer?.date else { return }
    self.recentDate = max(recentDate, fianceDate)
  }
  
  // MARK: - 유저 정보 불러오기
  private func getCurrentUser() {
    self.currentUser = UserManager.shared.currentUser
    self.currentUserName = currentUser?.name ?? "사용자"
  }
  private func getFianceUser() {
    self.fianceUser = UserManager.shared.fianceUser
    self.fianceName = fianceUser?.name ?? "상대방"
  }
  
  // MARK: - 대답 가져오기
  private func getMyAnswer() async throws {
    do {
      guard let userId = currentUser?.userId else { return }
      let myAnswer = try await UserManager.shared.getAnswer(userId: userId, questionId: self.dbQuestion.questionID)
      self.currentUserAnswer = myAnswer.answer
      self.currentUserAnswerId = myAnswer.answerId
      self.currentUserAnswerStatus = .answered
    } catch {
      self.currentUserAnswerStatus = .noAnswered
      self.currentUserReactionStatus = .noReact(.lock)
    }
  }
  
  private func getFianceAnswer() async throws {
    guard let fianceId = fianceUser?.userId else {
      self.fianceAnswerStatus = .unconnected
      self.fianceReactionStatus = .noReact(.lock)
      
      return
    }
    
    do {
      let fianceAnswer = try await UserManager.shared.getAnswer(userId: fianceId, questionId: self.dbQuestion.questionID)
      self.fianceAnswer = fianceAnswer.answer
      self.fianceAnswerId = fianceAnswer.answerId
      self.fianceAnswerStatus = .answered
    } catch {
      self.fianceAnswerStatus = .noAnswered
      self.fianceReactionStatus = .noReact(.lock)
    }
  }
  
  // MARK: - 반응 체크하기 -> 둘 다 긍정적이면 true
  @discardableResult
  private func checkReactions() -> Bool {
    let myReaction = checkMyReaction()
    let fianceReaction = checkFianceReaction()
    return myReaction && fianceReaction
  }
  
  private func checkMyReaction() -> Bool {
    guard let myReaction = self.currentUserAnswer?.reactionType else {
      self.currentUserReactionStatus = .noReact(.lock)
      return false
    }
    if myReaction == .error {
      if currentUserAnswerStatus == .answered && fianceAnswerStatus == .answered {
        self.currentUserReactionStatus = .noReact(.plus)
      } else {
        self.currentUserReactionStatus = .noReact(.lock)
      }
    } else {
      self.selectedReaction = .react(myReaction)
      self.currentUserReactionStatus = .react(myReaction)
    }
    return myReaction.isPositiveReact()
  }
  
  private func checkFianceReaction() -> Bool {
    guard let fianceReaction = self.fianceAnswer?.reactionType, fianceReaction != .error else {
      self.fianceReactionStatus = (currentUserReactionStatus.isReacted ? .noReact(.wait) : .noReact(.lock))
      return false
    }
    self.fianceReactionStatus = (currentUserReactionStatus.isReacted && fianceReaction != .error ? .react(fianceReaction) : .noReact(.lock))

    return fianceReaction.isPositiveReact()
  }
  
  // MARK: - 반응선택 뷰 관련
  func tapSelectReactionButton() {
    showSelectReactionView = true
  }
  
  func updateReaction() {
    showSelectReactionView = false
    guard let selectedReactionType = selectedReaction.reactionType else { return }
    guard let currentUserId = currentUser?.userId else { return }
    guard let currentUserAnswerId = currentUserAnswerId else { return }
    
    AnswerManager.shared.updateReaction(userId: currentUserId, answerId: currentUserAnswerId, reaction: selectedReactionType)
    updateAnswerComplete()
  }
  
  private func updateAnswerComplete() {
    let positive = checkReactions()
    
    guard let currentUserId = currentUser?.userId else { return }
    guard let fianceId = fianceUser?.userId else { return }
    guard let currentUserAnswerId = self.currentUserAnswerId else { return }
    guard let fianceAnswerId = self.fianceAnswerId else { return }
    
    AnswerManager.shared.updateAnswerComplete(userId: currentUserId, answerId: currentUserAnswerId, status: positive)
    AnswerManager.shared.updateAnswerComplete(userId: fianceId, answerId: fianceAnswerId, status: positive)
    
  }
}
