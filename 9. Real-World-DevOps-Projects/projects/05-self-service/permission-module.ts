import { createBackendModule } from '@backstage/backend-plugin-api';
import { policyExtensionPoint } from '@backstage/plugin-permission-node/alpha';
import { VeriqtaPermissionPolicy } from './permission-policy';
export default createBackendModule({
  pluginId: 'permission', moduleId: 'veriqta-policy',
  register(reg) {
    reg.registerInit({ deps: { policy: policyExtensionPoint },
      async init({ policy }) { policy.setPolicy(new VeriqtaPermissionPolicy()); },
    });
  },
});
