import starFindingCoreTest from './StarFindingCore.test';
import captureWorkflowCoordinatorTest from './CaptureWorkflowCoordinator.test';
import observationPlanningServiceTest from './ObservationPlanningService.test';
import skyDomeProjectionServiceTest from './SkyDomeProjectionService.test';
import huaweiArPoseAdapterTest from './HuaweiArPoseAdapter.test';

export default function testsuite() {
  starFindingCoreTest();
  captureWorkflowCoordinatorTest();
  observationPlanningServiceTest();
  skyDomeProjectionServiceTest();
  huaweiArPoseAdapterTest();
}
