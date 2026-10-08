import { HttpStatus, ValidationError, ValidationPipe } from '@nestjs/common';
import { AppError } from './errors';

function fieldPaths(errors: ValidationError[], prefix = ''): string[] {
  return errors.flatMap((e) => {
    const path = prefix ? `${prefix}.${e.property}` : e.property;
    return e.children?.length ? fieldPaths(e.children, path) : [path];
  });
}

/** Lists every invalid field so the app can highlight all of them at once (EX-06). */
export function createValidationPipe() {
  return new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
    exceptionFactory: (errors) => {
      const fields = fieldPaths(errors);
      if (fields.length > 0 && fields.every((f) => f.startsWith('address.'))) {
        return new AppError(HttpStatus.BAD_REQUEST, 'INVALID_ADDRESS', 'Please fill in the highlighted address fields.', {
          fields: fields.map((f) => f.slice('address.'.length)),
        });
      }
      return new AppError(HttpStatus.BAD_REQUEST, 'INVALID_INPUT', 'Please check the highlighted fields.', { fields });
    },
  });
}
