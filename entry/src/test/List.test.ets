import starFindingCoreTest from './StarFindingCore.test';
import captureWorkflowCoordinatorTest from './CaptureWorkflowCoordinator.test';
import observationPlanningServiceTest from './ObservationPlanningService.test';
import skyDomeProjectionServiceTest from './SkyDomeProjectionService.test';
import huaweiArPoseAdapterTest from './HuaweiArPoseAdapter.test';
import normalSkyProjectionServiceTest from './NormalSkyProjectionService.test';

export default function testsuite() {
  starFindingCoreTest();
  captureWorkflowCoordinatorTest();
  observationPlanningServiceTest();
  skyDomeProjectionServiceTest();
  huaweiArPoseAdapterTest();
  normalSkyProjectionServiceTest();
}
