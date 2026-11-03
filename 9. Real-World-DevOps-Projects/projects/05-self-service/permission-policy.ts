import { AuthorizeResult, isPermission, PolicyDecision } from '@backstage/plugin-permission-common';
import { PermissionPolicy, PolicyQuery, PolicyQueryUser } from '@backstage/plugin-permission-node';
import { actionExecutePermission, taskCreatePermission, taskReadPermission, taskCancelPermission, templateParameterReadPermission, templateStepReadPermission } from '@backstage/plugin-scaffolder-common/alpha';
import { createScaffolderActionConditionalDecision, scaffolderActionConditions, createScaffolderTaskConditionalDecision, scaffolderTaskConditions } from '@backstage/plugin-scaffolder-backend/alpha';

export class VeriqtaPermissionPolicy implements PermissionPolicy {
  async handle(request: PolicyQuery, user?: PolicyQueryUser): Promise<PolicyDecision> {
    const member = user?.info.ownershipEntityRefs.some(ref =>
      ['group:default/veriqta-platform', 'group:default/veriqta-payments'].includes(ref));
    if (!member) return { result: AuthorizeResult.DENY };
    if (isPermission(request.permission, actionExecutePermission)) {
      return createScaffolderActionConditionalDecision(request.permission, {
        anyOf: ['fetch:template', 'publish:github', 'catalog:register'].map(actionId =>
          scaffolderActionConditions.hasActionId({ actionId })),
      });
    }
    if (isPermission(request.permission, taskReadPermission) || isPermission(request.permission, taskCancelPermission)) {
      return createScaffolderTaskConditionalDecision(request.permission,
        scaffolderTaskConditions.isTaskOwner({ createdBy: [user!.info.userEntityRef] }));
    }
    if (isPermission(request.permission, taskCreatePermission) ||
        isPermission(request.permission, templateParameterReadPermission) ||
        isPermission(request.permission, templateStepReadPermission) ||
        request.permission.name === 'catalog.entity.read') return { result: AuthorizeResult.ALLOW };
    return { result: AuthorizeResult.DENY };
  }
}
