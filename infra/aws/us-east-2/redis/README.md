<!-- BEGIN_TF_DOCS -->

## Requirements

| Name                                                                     | Version |
| ------------------------------------------------------------------------ | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.0  |
| <a name="requirement_aws"></a> [aws](#requirement_aws)                   | >= 5.46 |

## Providers

No providers.

## Modules

| Name                                         | Source                        | Version |
| -------------------------------------------- | ----------------------------- | ------- |
| <a name="module_vpc"></a> [vpc](#module_vpc) | terraform-aws-modules/vpc/aws | n/a     |

## Resources

No resources.

## Inputs

| Name                                                                                                   | Description                                    | Type     | Default | Required |
| ------------------------------------------------------------------------------------------------------ | ---------------------------------------------- | -------- | ------- | :------: |
| <a name="input_name"></a> [name](#input_name)                                                          | Name for created resources and as a tag prefix | `string` | n/a     |   yes    |
| <a name="input_private_subnet_az1_cidr"></a> [private_subnet_az1_cidr](#input_private_subnet_az1_cidr) | The private subnet for az1                     | `string` | n/a     |   yes    |
| <a name="input_private_subnet_az2_cidr"></a> [private_subnet_az2_cidr](#input_private_subnet_az2_cidr) | The private subnet for az2                     | `string` | n/a     |   yes    |
| <a name="input_private_subnet_az3_cidr"></a> [private_subnet_az3_cidr](#input_private_subnet_az3_cidr) | The private subnet for az3                     | `string` | n/a     |   yes    |
| <a name="input_public_subnet_az1_cidr"></a> [public_subnet_az1_cidr](#input_public_subnet_az1_cidr)    | The public subnet for az1                      | `string` | n/a     |   yes    |
| <a name="input_public_subnet_az2_cidr"></a> [public_subnet_az2_cidr](#input_public_subnet_az2_cidr)    | The public subnet for az2                      | `string` | n/a     |   yes    |
| <a name="input_public_subnet_az3_cidr"></a> [public_subnet_az3_cidr](#input_public_subnet_az3_cidr)    | The public subnet for az3                      | `string` | n/a     |   yes    |
| <a name="input_region"></a> [region](#input_region)                                                    | The aws region for the vpc                     | `string` | n/a     |   yes    |
| <a name="input_vpc_cidr"></a> [vpc_cidr](#input_vpc_cidr)                                              | The vpc cidr block                             | `string` | n/a     |   yes    |

## Outputs

| Name                                                                                      | Description                    |
| ----------------------------------------------------------------------------------------- | ------------------------------ |
| <a name="output_private_subnet_ids"></a> [private_subnet_ids](#output_private_subnet_ids) | The created private subnet ids |
| <a name="output_public_subnet_ids"></a> [public_subnet_ids](#output_public_subnet_ids)    | The created public subnet ids  |
| <a name="output_vpc_id"></a> [vpc_id](#output_vpc_id)                                     | The created vpc_id             |

<!-- END_TF_DOCS -->
