import starFindingCoreTest from './StarFindingCore.test';
import captureWorkflowCoordinatorTest from './CaptureWorkflowCoordinator.test';
import observationPlanningServiceTest from './ObservationPlanningService.test';
import skyDomeProjectionServiceTest from './SkyDomeProjectionService.test';
import huaweiArPoseAdapterTest from './HuaweiArPoseAdapter.test';
import normalSkyProjectionServiceTest from './NormalSkyProjectionService.test';
import gestureInteractionTest from './GestureInteraction.test';
import normalSkySceneServiceTest from './NormalSkySceneService.test';
import normalSkyGestureControllerTest from './NormalSkyGestureController.test';
import normalSkyOrientationServiceTest from './NormalSkyOrientationService.test';
import normalSkyLayoutServiceTest from './NormalSkyLayoutService.test';
import ephemerisServiceTest from './EphemerisService.test';
import normalSkyViewStateServiceTest from './NormalSkyViewStateService.test';

export default function testsuite() {
  starFindingCoreTest();
  captureWorkflowCoordinatorTest();
  observationPlanningServiceTest();
  skyDomeProjectionServiceTest();
  huaweiArPoseAdapterTest();
  normalSkyProjectionServiceTest();
  gestureInteractionTest();
  normalSkySceneServiceTest();
  normalSkyGestureControllerTest();
  normalSkyOrientationServiceTest();
  normalSkyLayoutServiceTest();
  ephemerisServiceTest();
  normalSkyViewStateServiceTest();
}
