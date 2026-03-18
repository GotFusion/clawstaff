# core/contracts/

Shared contracts for cross-module communication.

## Scope

- Event contracts used by capture, storage, and orchestrator.
- Knowledge contracts used by knowledge and skills pipeline.
- Error/status code catalog shared by runtime modules.

## Current Contracts

- `CaptureEventContracts.swift`: `RawEvent`, `ContextSnapshot`, `NormalizedEvent`.
- `SemanticTargetContracts.swift`: `SemanticTarget`, `SemanticBoundingRect`, locator/source enums.
- `KnowledgeTaskContracts.swift`: `TaskChunk`, `TaskBoundaryReason`, `TaskSlicingPolicy`.
- `KnowledgeItemContracts.swift`: `KnowledgeItem`, `KnowledgeStep`, `KnowledgeContext`, `KnowledgeConstraint`, `KnowledgeSource`.
- `OrchestratorContracts.swift`: `OpenStaffMode`, `ModeTransitionContext`, `ModeTransitionDecision`, `OrchestratorLogEntry`.
- `AssistPredictionContracts.swift`: `AssistPredictionInput`, `AssistPredictionSignalMatch`, `AssistPredictionEvidence`, `AssistKnowledgeRetrievalResult`.
- `AssistModeContracts.swift`: `AssistSuggestion`, `AssistConfirmationDecision`, `AssistExecutionOutcome`, `AssistLoopLogEntry`.
- `StudentModeContracts.swift`: `StudentExecutionPlan`, `StudentStepExecutionResult`, `StudentReviewReport`, `StudentLoopLogEntry`.
- `OpenClawExecutionContracts.swift`: `OpenClawExecutionRequest`, `OpenClawExecutionResult`, `OpenClawGatewayExecutionPayload`, `OpenClawExecutionReview`.
- `TeacherQuickFeedbackContracts.swift`: `TeacherQuickFeedbackAction`, `TeacherQuickFeedbackShortcut`, `TeacherReviewEvidence`.
- `InteractionTurnContracts.swift`: `InteractionTurn`, `InteractionTurnStepReference`, `InteractionTurnExecutionLink`, `InteractionTurnReviewLink`.
- `NextStateEvidenceContracts.swift`: `NextStateEvidence`, `NextStateEvidenceTurnContext`, `NextStateEvaluativeCandidate`, `NextStateDirectiveCandidate`.
- `PreferenceSignalContracts.swift`: `PreferenceSignal`, `PreferenceSignalType`, `PreferenceSignalScopeReference`, `PreferenceSignalPromotionStatus`.

## Rule

Any payload crossing module boundaries must reference a contract defined in this directory.
