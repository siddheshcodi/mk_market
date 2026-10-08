import { Transform, Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsDefined,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { MAX_QTY_PER_ITEM } from '../common/rules';

const trim = Transform(({ value }) => (typeof value === 'string' ? value.trim() : value));

export class OrderItemDto {
  @IsUUID()
  productId!: string;

  @IsInt()
  @Min(1)
  @Max(MAX_QTY_PER_ITEM)
  qty!: number;
}

/** BR-07: house/flat, street/area and city are required; pincode is mandatory and 6 digits. */
export class AddressDto {
  @trim
  @IsString()
  @Length(2, 60)
  name!: string;

  @trim
  @IsString()
  @Length(1, 50)
  house!: string;

  @trim
  @IsString()
  @Length(2, 100)
  street!: string;

  @IsOptional()
  @trim
  @IsString()
  @Length(0, 100)
  landmark?: string;

  @trim
  @IsString()
  @Length(2, 50)
  city!: string;

  @trim
  @Matches(/^[1-9]\d{5}$/)
  pincode!: string;

  /** Map pin. Strongly recommended: it makes the 4 km road check accurate (spec OI-U8). */
  @IsOptional()
  @IsLatitude()
  lat?: number;

  @IsOptional()
  @IsLongitude()
  lng?: number;
}

export class CreateCheckoutDto {
  // An empty list is reported as EMPTY_ORDER by the service (BR-05).
  @IsDefined()
  @IsArray()
  @ArrayMaxSize(50)
  @ArrayUnique((item: OrderItemDto) => item?.productId)
  @ValidateNested({ each: true })
  @Type(() => OrderItemDto)
  items!: OrderItemDto[];

  // BR-06: no address, no payment.
  @IsDefined()
  @ValidateNested()
  @Type(() => AddressDto)
  address!: AddressDto;
}

export class ConfirmPaymentDto {
  @IsString()
  @Length(1, 64)
  gatewayOrderId!: string;

  @IsString()
  @Length(1, 64)
  gatewayPaymentId!: string;

  @IsString()
  @Length(1, 256)
  signature!: string;
}
